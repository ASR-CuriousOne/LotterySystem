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

contract LotteryEX is Initializable, UUPSUpgradeable, Ownable2StepUpgradeable, PausableUpgradeable, ReentrancyGuard {
    enum Phase {
        Open,
        Calculating,
        Drawn,
        Refundable
    }

    struct Round {
        uint256 ticketBitmap;
        address winner;
        uint16 ticketsSold;
        Phase phase;
        uint256 prizePool;
        uint256 startTime;
    }

    uint256 public ticketPrice;
    uint256 public roundDuration;
    uint256 public drawTimeout;
    uint256 public protocolFeeBps;
    uint256 public currentRoundId;
    address public treasury;

    bytes32 public keyHash;
    uint256 public subscriptionId;
    IVRFCoordinatorV2Plus public vrfCoordinator;

    mapping(uint256 => Round) public rounds;
    mapping(uint256 => mapping(uint256 => address)) public ticketOwners;
    mapping(address => uint256) public pendingWithdrawals;
    mapping(uint256 => uint256) public requestToRound;
    mapping(address => uint256) public userParticipationCount;

    error InvalidPhase();
    error IncorrectPayment();
    error TicketAlreadySold();
    error ConditionsNotMet();
    error TimeoutNotReached();
    error NotTicketOwner();
    error NoFundsToWithdraw();
    error TransferFailed();
    error ExceedsMaxTickets();
    error ZeroTickets();

    event RoundStarted(uint256 indexed roundId, uint256 startTime);
    event TicketsPurchased(uint256 indexed roundId, address indexed buyer, uint256 count);
    event RandomnessRequested(uint256 indexed roundId, uint256 requestId);
    event WinnerDrawn(uint256 indexed roundId, address indexed winner, uint256 amount);
    event RefundFallbackEnabled(uint256 indexed roundId);
    event RefundClaimed(uint256 indexed roundId, address indexed user, uint8 ticketIndex);
    error OnlyCoordinatorCanFulfill(address have, address want);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function getTicketPrice(address user) public view returns (uint256) {
        if (userParticipationCount[user] >= 5) {
            return (ticketPrice * 90) / 100;
        }
        return ticketPrice;
    }

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
        // casting to uint16 is mathematically safe because total tickets are capped at 256
        // forge-lint: disable-next-line(unsafe-typecast)
        round.ticketsSold = uint16(_ticketsSold + len);
        round.prizePool += msg.value;

        userParticipationCount[msg.sender] += len;

        emit TicketsPurchased(currentRoundId, msg.sender, len);
    }

    function checkUpkeep(bytes calldata) external view returns (bool upkeepNeeded, bytes memory) {
        Phase currentPhase = rounds[currentRoundId].phase;
        if (currentPhase != Phase.Open) return (false, "");

        uint16 _ticketsSold = rounds[currentRoundId].ticketsSold;
        if (_ticketsSold == 0) return (false, "");

        bool timeExpired = block.timestamp >= rounds[currentRoundId].startTime + roundDuration;
        bool soldOut = _ticketsSold == 256;

        return (timeExpired || soldOut, "");
    }

    function performUpkeep(bytes calldata) external whenNotPaused {
        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Open) revert ConditionsNotMet();

        uint16 _ticketsSold = round.ticketsSold;
        if (_ticketsSold == 0) revert ConditionsNotMet();

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

    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        if (msg.sender != address(vrfCoordinator)) {
            revert OnlyCoordinatorCanFulfill(msg.sender, address(vrfCoordinator));
        }
        fulfillRandomWords(requestId, randomWords);
    }

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

    function withdrawPrize() external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NoFundsToWithdraw();

        pendingWithdrawals[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    function enableRefundFallback() external {
        Round storage round = rounds[currentRoundId];
        if (round.phase != Phase.Calculating) revert InvalidPhase();
        if (block.timestamp < round.startTime + roundDuration + drawTimeout) revert TimeoutNotReached();

        round.phase = Phase.Refundable;
        emit RefundFallbackEnabled(currentRoundId);

        currentRoundId++;
        rounds[currentRoundId].startTime = block.timestamp;
        rounds[currentRoundId].phase = Phase.Open;
        emit RoundStarted(currentRoundId, block.timestamp);
    }

    function claimRefund(uint256 roundId, uint8 ticketIndex) external nonReentrant {
        Round storage round = rounds[roundId];
        if (round.phase != Phase.Refundable) revert InvalidPhase();
        if (ticketOwners[roundId][ticketIndex] != msg.sender) revert NotTicketOwner();

        ticketOwners[roundId][ticketIndex] = address(0);
        pendingWithdrawals[msg.sender] += ticketPrice;

        emit RefundClaimed(roundId, msg.sender, ticketIndex);
    }
}
