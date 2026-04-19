// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {
    VRFCoordinatorV2Interface
} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title VRF-Powered Lottery
 * @notice An alternative implementation using Chainlink VRF for provably fair randomness.
 */
contract LotteryVRF is VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    enum Phase {
        Open,
        Calculating,
        Drawn
    }

    Phase public currentPhase;

    // forge-lint: disable-next-line(screaming-snake-case-immutable)
    uint256 public immutable ticketPrice;
    uint256 public prizePool;
    address public winner;
    address[] public participants;

    // --- Chainlink VRF Variables ---
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;
    bytes32 public immutable KEY_HASH;
    uint64 public immutable SUBSCRIPTION_ID;
    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;
    uint32 public constant NUM_WORDS = 1;

    error InvalidPhase();
    error IncorrectPayment();
    error NotWinner();
    error TransferFailed();

    event TicketPurchased(address indexed buyer);
    event RandomnessRequested(uint256 requestId);
    event WinnerDrawn(address indexed winner);

    constructor(uint256 _ticketPrice, address _vrfCoordinator, bytes32 _keyHash, uint64 _subscriptionId)
        VRFConsumerBaseV2(_vrfCoordinator)
        Ownable(msg.sender)
    {
        ticketPrice = _ticketPrice;
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        KEY_HASH = _keyHash;
        SUBSCRIPTION_ID = _subscriptionId;
        currentPhase = Phase.Open;
    }

    function buyTicket() external payable {
        if (currentPhase != Phase.Open) revert InvalidPhase();
        if (msg.value != ticketPrice) revert IncorrectPayment();

        participants.push(msg.sender);
        prizePool += msg.value;
        emit TicketPurchased(msg.sender);
    }

    /**
     * @notice Replaces closeSale() and commitHash(). Requests randomness from Chainlink.
     */
    function closeSaleAndDraw() external onlyOwner returns (uint256 requestId) {
        if (currentPhase != Phase.Open) revert InvalidPhase();
        require(participants.length > 0, "No participants");

        currentPhase = Phase.Calculating;

        // Will revert if subscription is not funded
        requestId = VRF_COORDINATOR.requestRandomWords(
            KEY_HASH, SUBSCRIPTION_ID, REQUEST_CONFIRMATIONS, CALLBACK_GAS_LIMIT, NUM_WORDS
        );

        emit RandomnessRequested(requestId);
    }

    /**
     * @notice The callback function called by the Chainlink Oracle.
     */
    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] memory randomWords
    )
        internal
        override
    {
        uint256 winnerIndex = randomWords[0] % participants.length;
        winner = participants[winnerIndex];
        currentPhase = Phase.Drawn;

        emit WinnerDrawn(winner);
    }

    function claimPrize() external nonReentrant {
        if (currentPhase != Phase.Drawn) revert InvalidPhase();
        if (msg.sender != winner) revert NotWinner();

        uint256 amount = prizePool;
        prizePool = 0; // CEI pattern

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}
