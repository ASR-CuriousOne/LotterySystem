// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {
    VRFCoordinatorV2Interface
} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {
    AutomationCompatibleInterface
} from "chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";

/**
 * @title Lottery Extended
 * @notice A fully autonomous, perpetual, and gas-optimized lottery system.
 * @dev Implements Chainlink VRF, Chainlink Keepers, Bitmap storage, and Pull-Over-Push vaults.
 */
contract LotteryEX is VRFConsumerBaseV2, AutomationCompatibleInterface, ReentrancyGuard {
    /// @notice Defines the discrete lifecycle states of a single lottery round.
    enum Phase {
        Open,
        Calculating,
        Drawn,
        Refundable
    }

    /// @notice Encapsulates all state data for a specific lottery round.
    struct Round {
        Phase phase;
        uint256 startTime;
        uint256 prizePool;
        address winner;
        uint256 ticketBitmap; // Bits 0-255 track ticket availability
        uint16 ticketsSold;
    }

    // --- State Variables ---

    /// @notice The fixed entry cost per ticket in wei.
    uint256 public immutable TICKET_PRICE;

    /// @notice The minimum time in seconds a round must remain open before upkeep can be performed.
    uint256 public immutable ROUND_DURATION;

    /// @notice The time allowed for the oracle to respond before a round is declared void.
    uint256 public immutable DRAW_TIMEOUT;

    /// @notice The auto-incrementing ID tracking the currently active lottery round.
    uint256 public currentRoundId;

    /// @notice Maps a round ID to its corresponding Round state data.
    mapping(uint256 => Round) public rounds;

    /// @notice Maps a round ID and ticket index (0-255) to the purchasing user's address.
    mapping(uint256 => mapping(uint256 => address)) public ticketOwners;

    /// @notice Vault tracking the safely withdrawable ETH balance for each user.
    mapping(address => uint256) public pendingWithdrawals;

    /// @notice Maps a Chainlink VRF request ID to the round ID that triggered it.
    mapping(uint256 => uint256) public requestToRound;

    // --- Chainlink VRF Configurations ---

    /// @notice The Chainlink VRF Coordinator contract interface.
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;

    /// @notice The gas lane key hash value for the VRF request.
    bytes32 public immutable KEY_HASH;

    /// @notice The ID of the funded Chainlink VRF subscription.
    uint64 public immutable SUBSCRIPTION_ID;

    /// @notice The number of block confirmations required before fulfilling the request.
    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    /// @notice The gas limit for the callback fulfillRandomWords function.
    uint32 public constant CALLBACK_GAS_LIMIT = 200000;

    /// @notice The number of random words to request from the oracle.
    uint32 public constant NUM_WORDS = 1;

    // --- Errors ---

    /// @notice Thrown when an action is attempted in the wrong lifecycle phase.
    error InvalidPhase();

    /// @notice Thrown when the msg.value does not exactly match the ticket price.
    error IncorrectPayment();

    /// @notice Thrown when a user attempts to buy a ticket index that is already claimed.
    error TicketAlreadySold();

    /// @notice Thrown when upkeep is triggered before the deadline or ticket cap is met.
    error ConditionsNotMet();

    /// @notice Thrown when the refund fallback is triggered before the oracle timeout has expired.
    error TimeoutNotReached();

    /// @notice Thrown when a user attempts to refund a ticket they do not own.
    error NotTicketOwner();

    /// @notice Thrown when a user attempts to withdraw from an empty vault balance.
    error NoFundsToWithdraw();

    /// @notice Thrown when the ETH transfer to the user fails.
    error TransferFailed();

    // --- Events ---

    /// @notice Emitted when a new lottery round begins.
    /// @param roundId The ID of the newly started round.
    /// @param startTime The block timestamp when the round opened.
    event RoundStarted(uint256 indexed roundId, uint256 startTime);

    /// @notice Emitted when a user successfully purchases a ticket.
    /// @param roundId The round in which the ticket was bought.
    /// @param buyer The address of the ticket purchaser.
    /// @param ticketIndex The chosen ticket number (0-255).
    event TicketPurchased(uint256 indexed roundId, address indexed buyer, uint8 ticketIndex);

    /// @notice Emitted when the automation triggers the VRF randomness request.
    /// @param roundId The round requesting the draw.
    /// @param requestId The unique ID assigned to the Chainlink VRF request.
    event RandomnessRequested(uint256 indexed roundId, uint256 requestId);

    /// @notice Emitted when the oracle callback selects the final winner.
    /// @param roundId The round that was drawn.
    /// @param winner The address of the winning participant.
    /// @param amount The total ETH allocated to the winner's vault.
    event WinnerDrawn(uint256 indexed roundId, address indexed winner, uint256 amount);

    /// @notice Emitted when a round fails to draw and is opened for manual refunds.
    /// @param roundId The ID of the voided round.
    event RefundFallbackEnabled(uint256 indexed roundId);

    /// @notice Emitted when a user successfully reclaims their ticket cost from a voided round.
    /// @param roundId The voided round ID.
    /// @param user The address of the refunded user.
    /// @param ticketIndex The ticket index that was refunded.
    event RefundClaimed(uint256 indexed roundId, address indexed user, uint8 ticketIndex);

    /// @notice Emitted when a user withdraws ETH from their pending withdrawals vault.
    /// @param user The address withdrawing funds.
    /// @param amount The amount of ETH withdrawn.
    event VaultWithdrawn(address indexed user, uint256 amount);

    /**
     * @notice Initializes the permanent multi-round lottery engine.
     * @param _ticketPrice The cost of a single ticket in wei.
     * @param _roundDuration The minimum time in seconds before a round can be drawn.
     * @param _drawTimeout The maximum time to wait for the VRF oracle before allowing refunds.
     * @param _vrfCoordinator The address of the Chainlink VRF Coordinator.
     * @param _keyHash The key hash for the network's gas lane.
     * @param _subscriptionId The Chainlink subscription ID.
     */
    constructor(
        uint256 _ticketPrice,
        uint256 _roundDuration,
        uint256 _drawTimeout,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        TICKET_PRICE = _ticketPrice;
        ROUND_DURATION = _roundDuration;
        DRAW_TIMEOUT = _drawTimeout;

        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        KEY_HASH = _keyHash;
        SUBSCRIPTION_ID = _subscriptionId;

        // Initialize Round 1
        currentRoundId = 1;
        rounds[1].startTime = block.timestamp;
        rounds[1].phase = Phase.Open;
    }

    /**
     * @notice Purchases a specific ticket number between 0 and 255 using gas-efficient bitmaps.
     * @param ticketIndex The chosen ticket number (0-255).
     */
    function buyTicket(uint8 ticketIndex) external payable nonReentrant {
        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Open) revert InvalidPhase();
        if (msg.value != TICKET_PRICE) revert IncorrectPayment();

        // Bitwise check to ensure the ticket isn't already sold
        if ((round.ticketBitmap & (uint256(1) << ticketIndex)) != 0) revert TicketAlreadySold();

        // Mark ticket as sold
        round.ticketBitmap |= (uint256(1) << ticketIndex);
        round.ticketsSold += 1;
        round.prizePool += msg.value;
        ticketOwners[currentRoundId][ticketIndex] = msg.sender;

        emit TicketPurchased(currentRoundId, msg.sender, ticketIndex);
    }

    // ==========================================
    // CHAINLINK AUTOMATION (KEEPERS)
    // ==========================================

    /**
     * @notice Called off-chain by Chainlink Nodes to see if the round should end.
     * @dev Upkeep is needed if the time duration expired OR all 256 tickets sold out early.
     * @param checkData Unused calldata parameter required by the Chainlink interface.
     * @return upkeepNeeded Boolean indicating if the performUpkeep function should be called.
     * @return performData Empty bytes array required by the Chainlink interface.
     */
    function checkUpkeep(bytes calldata checkData)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        checkData; // Silence unused parameter warning

        Round memory round = rounds[currentRoundId];

        bool timeExpired = block.timestamp >= round.startTime + ROUND_DURATION;
        bool soldOut = round.ticketsSold == 256;
        bool hasPlayers = round.ticketsSold > 0;

        upkeepNeeded = round.phase == Phase.Open && hasPlayers && (timeExpired || soldOut);

        return (upkeepNeeded, "");
    }

    /**
     * @notice Automatically executed by Chainlink Nodes when checkUpkeep returns true.
     * @dev Transitions phase to Calculating and triggers the VRF Oracle request.
     * @param performData Unused bytes data provided by checkUpkeep.
     */
    function performUpkeep(bytes calldata performData) external override {
        performData; // Silence unused parameter warning

        Round storage round = rounds[currentRoundId];

        bool timeExpired = block.timestamp >= round.startTime + ROUND_DURATION;
        bool soldOut = round.ticketsSold == 256;

        if (round.phase != Phase.Open || round.ticketsSold == 0 || (!timeExpired && !soldOut)) {
            revert ConditionsNotMet();
        }

        round.phase = Phase.Calculating;

        uint256 requestId = VRF_COORDINATOR.requestRandomWords(
            KEY_HASH, SUBSCRIPTION_ID, REQUEST_CONFIRMATIONS, CALLBACK_GAS_LIMIT, NUM_WORDS
        );

        requestToRound[requestId] = currentRoundId;
        emit RandomnessRequested(currentRoundId, requestId);
    }

    // ==========================================
    // CHAINLINK VRF (CALLBACK)
    // ==========================================

    /**
     * @notice Handles the random number delivery and selects the winner using the bitmap.
     * @dev Employs a deterministic rollover loop to bypass unsold ticket bits.
     * @param requestId The ID of the fulfilled VRF request.
     * @param randomWords The array of random numbers provided by the oracle.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 roundId = requestToRound[requestId];
        Round storage round = rounds[roundId];

        if (round.phase != Phase.Calculating) return;

        // Modulo bias is physically impossible here since 256 is a power of 2
        uint256 winningIndex = randomWords[0] % 256;
        uint256 bitmap = round.ticketBitmap;

        // If VRF picks an unsold ticket, deterministically roll over to the next sold one
        // Guaranteed to terminate because performUpkeep requires ticketsSold > 0
        while ((bitmap & (uint256(1) << winningIndex)) == 0) {
            winningIndex = (winningIndex + 1) % 256;
        }

        address winner = ticketOwners[roundId][winningIndex];
        round.winner = winner;
        round.phase = Phase.Drawn;

        // PULL OVER PUSH: Route funds to the vault, not the wallet
        pendingWithdrawals[winner] += round.prizePool;
        emit WinnerDrawn(roundId, winner, round.prizePool);

        // INSTANT RESTART: Engine never sleeps
        currentRoundId++;
        rounds[currentRoundId].startTime = block.timestamp;
        rounds[currentRoundId].phase = Phase.Open;
        emit RoundStarted(currentRoundId, block.timestamp);
    }

    // ==========================================
    // PULL-OVER-PUSH & LIVENESS GUARDS
    // ==========================================

    /**
     * @notice Allows winners or refunded players to securely withdraw their ETH.
     * @dev Protects against DoS via malicious receive() fallbacks and follows CEI.
     */
    function withdrawPrize() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoFundsToWithdraw();

        pendingWithdrawals[msg.sender] = 0; // CEI Pattern

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit VaultWithdrawn(msg.sender, amount);
    }

    /**
     * @notice LIVENESS GUARD: If the VRF Oracle crashes or ignores the request,
     * this allows anyone to flag the stuck round as refundable.
     * @dev Enforces a strict timeout period before permitting the fallback transition.
     */
    function enableRefundFallback() external {
        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Calculating) revert InvalidPhase();

        // Ensure a generous timeout has passed since the round was supposed to end
        if (block.timestamp < round.startTime + ROUND_DURATION + DRAW_TIMEOUT) revert TimeoutNotReached();

        round.phase = Phase.Refundable;
        emit RefundFallbackEnabled(currentRoundId);

        // Restart the engine so the protocol survives the oracle outage
        currentRoundId++;
        rounds[currentRoundId].startTime = block.timestamp;
        rounds[currentRoundId].phase = Phase.Open;
        emit RoundStarted(currentRoundId, block.timestamp);
    }

    /**
     * @notice Allows a user to claim a refund for a specific ticket if the round failed.
     * @dev Routes the refund amount to the pull-over-push vault to maintain state safety.
     * @param roundId The ID of the voided round.
     * @param ticketIndex The specific ticket number being refunded.
     */
    function claimRefund(uint256 roundId, uint8 ticketIndex) external nonReentrant {
        Round storage round = rounds[roundId];
        if (round.phase != Phase.Refundable) revert InvalidPhase();
        if (ticketOwners[roundId][ticketIndex] != msg.sender) revert NotTicketOwner();

        // Zero out ownership to prevent double-spending
        ticketOwners[roundId][ticketIndex] = address(0);

        // Move funds to the vault
        pendingWithdrawals[msg.sender] += TICKET_PRICE;
        emit RefundClaimed(roundId, msg.sender, ticketIndex);
    }
}
