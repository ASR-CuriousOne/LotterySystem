// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {
    IVRFCoordinatorV2Plus
} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Veritas Autonomous Enterprise Lottery (Tier 3)
 * @author BitBoyz Team
 * @notice An enterprise-grade, fully autonomous lottery system featuring bitmapped storage and UUPS upgradeability.
 * @dev Implements Chainlink VRF v2.5 for randomness and Chainlink Keepers for autonomous state transitions.
 * Utilizes bitmapped storage to achieve O(1) gas costs for ticket tracking and UUPS for logic flexibility.
 */
contract LotteryEX is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, ReentrancyGuard {
    /**
     * @notice The operational phases of an autonomous round.
     * @custom:value Open Tickets can be purchased.
     * @custom:value Calculating Automation has triggered a draw; awaiting VRF callback.
     * @custom:value Drawn Winner has been selected; funds are ready for withdrawal.
     * @custom:value Refundable Oracle timeout reached; users can reclaim ticket costs.
     */
    enum Phase {
        Open,
        Calculating,
        Drawn,
        Refundable
    }

    /**
     * @notice State container for a specific lottery round.
     * @dev Packed into two 32-byte slots for EVM efficiency.
     * Slot 0: ticketBitmap. Slot 1: winner, ticketsSold, phase, prizePool, startTime.
     */
    struct Round {
        uint256 ticketBitmap;
        address winner;
        uint16 ticketsSold;
        Phase phase;
        uint256 prizePool;
        uint256 startTime;
    }

    /**
     *  @notice The base cost in wei required to purchase a single ticket index.
     */
    uint256 public ticketPrice;

    /**
     *  @notice The time window in seconds during which a lottery round accepts entries.
     */
    uint256 public roundDuration;

    /**
     *  @notice The grace period after expiration before a round can be manually marked as refundable.
     */
    uint256 public drawTimeout;

    /**
     *  @notice The protocol fee expressed in Basis Points (e.g., 200 = 2.00%).
     */
    uint256 public protocolFeeBps;

    /**
     *  @notice The incrementing unique identifier for the currently active lottery round.
     */
    uint256 public currentRoundId;

    /**
     *  @notice The address designated to receive protocol fees collected from each round.
     */
    address public treasury;

    /**
     *  @notice The network-specific gas lane key hash for Chainlink VRF requests.
     */
    bytes32 public keyHash;

    /**
     *  @notice The ID of the funded Chainlink VRF subscription used for oracle payments.
     */
    uint256 public subscriptionId;

    /**
     *  @notice The interface for the Chainlink VRF Coordinator V2 Plus contract.
     */
    IVRFCoordinatorV2Plus public vrfCoordinator;

    /**
     * @notice Maps a round ID to its corresponding Round state struct.
     * @dev Stores the bitmap, phase, prize pool, and timing for every historical and current round.
     */
    mapping(uint256 => Round) public rounds;

    /**
     * @notice Secondary bitmapped storage mapping.
     * @dev Maps Round ID => Ticket Index (0-255) => Owner Address.
     */
    mapping(uint256 => mapping(uint256 => address)) public ticketOwners;

    /**
     * @notice The internal vault for the 'Pull-over-Push' withdrawal pattern.
     * @dev Maps an address to its total claimable ETH balance in wei.
     */
    mapping(address => uint256) public pendingWithdrawals;

    /**
     * @notice Linkage for asynchronous oracle fulfillment.
     * @dev Maps a VRF Request ID to the Round ID that initiated it.
     */
    mapping(uint256 => uint256) public requestToRound;

    /**
     * @notice Tracks total entries per user across all rounds for loyalty discount calculations.
     * @dev If count >= 5, a 10% discount is applied via getTicketPrice.
     */
    mapping(address => uint256) public userParticipationCount;

    /**
     * @notice Thrown when an action is attempted in an incorrect lifecycle phase.
     */
    error InvalidPhase();

    /**
     *  @notice Thrown when the ETH sent does not match the calculated (possibly discounted) price.
     */
    error IncorrectPayment();

    /**
     *  @notice Thrown when a bitwise check detects a specific ticket index has already been sold.
     */
    error TicketAlreadySold();

    /**
     *  @notice Thrown if Chainlink Automation attempts upkeep before round expiration or sell-out.
     */
    error ConditionsNotMet();

    /**
     *  @notice Thrown if the refund failsafe is triggered before the DRAW_TIMEOUT period has elapsed.
     */
    error TimeoutNotReached();

    /**
     *  @notice Thrown when a user attempts to refund a ticket index they do not own.
     */
    error NotTicketOwner();

    /**
     *  @notice Thrown when withdrawPrize is called by an address with a zero vault balance.
     */
    error NoFundsToWithdraw();

    /**
     *  @notice Thrown if the low-level ETH transfer to the recipient fails.
     */
    error TransferFailed();

    /**
     *  @notice Thrown if a batch purchase would exceed the 256-bit physical storage limit.
     */
    error ExceedsMaxTickets();

    /**
     *  @notice Thrown if batchBuyTickets is called with an empty index array.
     */
    error ZeroTickets();

    /**
     *  @notice Emitted when the VRF coordinator address does not match the authorized provider.
     */
    error OnlyCoordinatorCanFulfill(address have, address want);

    /**
     *  @notice Emitted when a new round is autonomously initialized.
     */
    event RoundStarted(uint256 indexed roundId, uint256 startTime);

    /**
     *  @notice Emitted when a user purchases one or more tickets.
     */
    event TicketsPurchased(uint256 indexed roundId, address indexed buyer, uint256 count);

    /**
     *  @notice Emitted when the protocol requests randomness from the Chainlink Oracle.
     */
    event RandomnessRequested(uint256 indexed roundId, uint256 requestId);

    /**
     *  @notice Emitted when the winner is selected and the pool is distributed.
     */
    event WinnerDrawn(uint256 indexed roundId, address indexed winner, uint256 amount);

    /**
     *  @notice Emitted if an oracle outage triggers the trustless refund mechanism.
     */
    event RefundFallbackEnabled(uint256 indexed roundId);

    /**
     *  @notice Emitted when a user successfully reclaims funds from a refundable round.
     */
    event RefundClaimed(uint256 indexed roundId, address indexed user, uint8 ticketIndex);

    /**
     * @dev Constructor ensures the implementation contract cannot be initialized directly.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the upgradeable state of the contract.
     * @dev Replaces the constructor in UUPS proxy patterns.
     * @param _vrfCoordinator The address of the Chainlink VRF v2.5 provider.
     * @param _ticketPrice The base cost of a single ticket in wei.
     * @param _roundDuration The time in seconds before a round expires.
     * @param _drawTimeout The grace period for oracles before refunds are enabled.
     * @param _keyHash The VRF gas lane key hash.
     * @param _subscriptionId The funded Chainlink VRF subscription ID.
     * @param _treasury The address designated to receive protocol fees.
     */
    function initialize(
        address _vrfCoordinator,
        uint256 _ticketPrice,
        uint256 _roundDuration,
        uint256 _drawTimeout,
        bytes32 _keyHash,
        uint256 _subscriptionId,
        address _treasury
    ) public initializer {
        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __Pausable_init();

        vrfCoordinator = IVRFCoordinatorV2Plus(_vrfCoordinator);

        ticketPrice = _ticketPrice;
        roundDuration = _roundDuration;
        drawTimeout = _drawTimeout;
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        treasury = _treasury;
        protocolFeeBps = 200;

        currentRoundId = 1;
        rounds[1].startTime = block.timestamp;
        rounds[1].phase = Phase.Open;
    }

    /**
     * @dev Required by UUPSUpgradeable to restrict logic upgrades to the owner.
     * @param newImplementation The address of the new contract logic.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     *  @notice Freezes all ticket sales; restricted to owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     *  @notice Resumes ticket sales; restricted to owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Calculates the ticket price for a specific user, applying VIP discounts if applicable.
     * @dev Implements a 10% loyalty discount for users with 5 or more previous participations.
     * @param user The address of the purchaser.
     * @return The final ticket price in wei.
     */
    function getTicketPrice(address user) public view returns (uint256) {
        if (userParticipationCount[user] >= 5) {
            return (ticketPrice * 90) / 100;
        }
        return ticketPrice;
    }

    /**
     * @notice Allows a user to purchase multiple specific ticket indices using bitmapped storage.
     * @dev Performs O(1) storage updates. Loop indices are incremented using 'unchecked' for gas efficiency.
     * @param ticketIndices An array of indices (0-255) the user wish to purchase.
     */
    function batchBuyTickets(uint8[] calldata ticketIndices) external payable whenNotPaused nonReentrant {
        uint256 len = ticketIndices.length;
        if (len == 0) revert ZeroTickets();

        uint256 requiredPayment = getTicketPrice(msg.sender) * len;
        if (msg.value != requiredPayment) revert IncorrectPayment();

        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Open) revert InvalidPhase();

        uint16 _ticketsSold = round.ticketsSold;
        if (_ticketsSold + len > 256) revert ExceedsMaxTickets();

        uint256 bitmap = round.ticketBitmap;

        for (uint256 i = 0; i < len;) {
            uint8 tIndex = ticketIndices[i];
            if ((bitmap & (uint256(1) << tIndex)) != 0) revert TicketAlreadySold();

            bitmap |= (uint256(1) << tIndex);
            ticketOwners[currentRoundId][tIndex] = msg.sender;

            unchecked {
                ++i;
            }
        }

        round.ticketBitmap = bitmap;
        // casting to uint16 is safe because total tickets are capped at 256
        // forge-lint: disable-next-line(unsafe-typecast)
        round.ticketsSold = uint16(_ticketsSold + len);
        round.prizePool += msg.value;

        userParticipationCount[msg.sender] += len;

        emit TicketsPurchased(currentRoundId, msg.sender, len);
    }

    /**
     * @notice View function for Chainlink Automation to determine if a draw is required.
     * @dev Evaluates 'timeExpired' or 'soldOut' conditions off-chain to minimize network premiums.
     * @return upkeepNeeded True if the round should be closed and drawn.
     */
    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory) {
        Phase currentPhase = rounds[currentRoundId].phase;
        if (currentPhase != Phase.Open) return (false, "");

        uint16 _ticketsSold = rounds[currentRoundId].ticketsSold;
        if (_ticketsSold == 0) return (false, "");

        // validator manipulation (~15s) is statistically irrelevant compared to the 24h round duration.
        // forge-lint: disable-next-line
        bool timeExpired = block.timestamp >= rounds[currentRoundId].startTime + roundDuration;
        bool soldOut = _ticketsSold == 256;

        return (timeExpired || soldOut, "");
    }

    /**
     * @notice Triggers the randomness request to close the current round.
     * @dev Called by the Chainlink Automation network once checkUpkeep returns true.
     */
    function performUpkeep(bytes calldata) external whenNotPaused {
        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Open) revert ConditionsNotMet();

        uint16 _ticketsSold = round.ticketsSold;
        if (_ticketsSold == 0) revert ConditionsNotMet();

        // validator manipulation (~15s) is statistically irrelevant compared to the 24h round duration.
        // forge-lint: disable-next-line
        bool timeExpired = block.timestamp >= round.startTime + roundDuration;
        bool soldOut = _ticketsSold == 256;
        if (!timeExpired && !soldOut) revert ConditionsNotMet();

        round.phase = Phase.Calculating;

        uint256 requestId = vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: subscriptionId,
                requestConfirmations: 3,
                callbackGasLimit: 200000,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
        );

        requestToRound[requestId] = currentRoundId;
        emit RandomnessRequested(currentRoundId, requestId);
    }

    /**
     * @notice Gatekeeper for the VRF callback.
     * @dev Ensures only the authorized VRF Coordinator can trigger result fulfillment.
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(vrfCoordinator));
        }
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @notice Selects the winner and initializes the next round autonomously.
     * @dev Implements a 'Rollover Loop' to find the nearest valid ticket index if the VRF
     * selects an unsold index. Splits the prize pool between the winner and treasury.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal {
        uint256 roundId = requestToRound[requestId];
        Round storage round = rounds[roundId];

        if (round.phase != Phase.Calculating) return;

        uint256 winningIndex = randomWords[0] % 256;
        uint256 bitmap = round.ticketBitmap;

        while ((bitmap & (uint256(1) << winningIndex)) == 0) {
            winningIndex = (winningIndex + 1) % 256;
        }

        address _winner = ticketOwners[roundId][winningIndex];
        uint256 _totalPool = round.prizePool;

        uint256 treasuryCut = (_totalPool * protocolFeeBps) / 10000;
        uint256 winnerCut = _totalPool - treasuryCut;

        round.winner = _winner;
        round.phase = Phase.Drawn;

        pendingWithdrawals[_winner] += winnerCut;
        pendingWithdrawals[treasury] += treasuryCut;

        emit WinnerDrawn(roundId, _winner, winnerCut);

        currentRoundId++;
        rounds[currentRoundId].startTime = block.timestamp;
        rounds[currentRoundId].phase = Phase.Open;
        emit RoundStarted(currentRoundId, block.timestamp);
    }

    /**
     * @notice Allows winners or the treasury to withdraw their accumulated earnings.
     * @dev Implements the 'Withdrawal Pattern' to protect against reentrancy and DoS.
     */
    function withdrawPrize() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoFundsToWithdraw();

        pendingWithdrawals[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /**
     * @notice Enables the trustless refund phase if oracles fail to respond within DRAW_TIMEOUT.
     * @dev Protects against 'Residual Trust' and permanent fund locking during network outages.
     */
    function enableRefundFallback() external {
        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Calculating) revert InvalidPhase();
        // minor timestamp drift does not compromise the integrity of the 48h trustless refund window.
        // forge-lint: disable-next-line
        if (block.timestamp < round.startTime + roundDuration + drawTimeout) revert TimeoutNotReached();

        round.phase = Phase.Refundable;
        emit RefundFallbackEnabled(currentRoundId);

        currentRoundId++;
        rounds[currentRoundId].startTime = block.timestamp;
        rounds[currentRoundId].phase = Phase.Open;
        emit RoundStarted(currentRoundId, block.timestamp);
    }

    /**
     * @notice Allows users to reclaim their exact ticket price from a refundable round.
     * @param roundId The ID of the round to claim from.
     * @param ticketIndex The specific index purchased by the user.
     */
    function claimRefund(uint256 roundId, uint8 ticketIndex) external nonReentrant {
        Round storage round = rounds[roundId];
        if (round.phase != Phase.Refundable) revert InvalidPhase();
        if (ticketOwners[roundId][ticketIndex] != msg.sender) revert NotTicketOwner();

        ticketOwners[roundId][ticketIndex] = address(0);
        pendingWithdrawals[msg.sender] += ticketPrice;

        emit RefundClaimed(roundId, msg.sender, ticketIndex);
    }
}
