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
 * @dev Inherits from VRFConsumerBaseV2, Ownable, and ReentrancyGuard.
 */
contract LotteryVRF is VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    /// @notice Represents the current operational state of the lottery
    enum Phase {
        Open,
        Calculating,
        Drawn
    }

    /// @notice The current phase of the lottery lifecycle
    Phase public currentPhase;

    /// @notice The fixed cost to enter the lottery
    uint256 public immutable TICKET_PRICE;

    /// @notice The total amount of ETH collected from ticket sales
    uint256 public prizePool;

    /// @notice The address of the randomly selected winner
    address public winner;

    /// @notice Array containing all ticket purchaser addresses
    address[] public participants;

    // --- Chainlink VRF Variables ---
    /// @notice The Chainlink VRF Coordinator contract interface
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;

    /// @notice The gas lane key hash value for the VRF request
    bytes32 public immutable KEY_HASH;

    /// @notice The ID of the funded Chainlink VRF subscription
    uint64 public immutable SUBSCRIPTION_ID;

    /// @notice The number of block confirmations required before fulfilling the request
    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    /// @notice The gas limit for the callback fulfillRandomWords function
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;

    /// @notice The number of random words to request from the oracle
    uint32 public constant NUM_WORDS = 1;

    // --- Custom Errors ---
    /// @notice Thrown when an action is attempted in the wrong lifecycle phase
    error InvalidPhase();

    /// @notice Thrown when the msg.value does not exactly match the ticket price
    error IncorrectPayment();

    /// @notice Thrown when a non-winner attempts to claim the prize
    error NotWinner();

    /// @notice Thrown when the ETH transfer to the winner fails
    error TransferFailed();

    // --- Events ---
    /// @notice Emitted when a user successfully purchases a ticket
    /// @param buyer The address of the ticket purchaser
    event TicketPurchased(address indexed buyer);

    /// @notice Emitted when the owner triggers the VRF randomness request
    /// @param requestId The unique ID assigned to the Chainlink VRF request
    event RandomnessRequested(uint256 requestId);

    /// @notice Emitted when the oracle callback selects the final winner
    /// @param winner The address of the winning participant
    event WinnerDrawn(address indexed winner);

    /**
     * @notice Initializes the VRF lottery contract.
     * @param _ticketPrice The cost of a single ticket in wei.
     * @param _vrfCoordinator The address of the Chainlink VRF Coordinator.
     * @param _keyHash The key hash for the network's gas lane.
     * @param _subscriptionId The Chainlink subscription ID.
     */
    constructor(uint256 _ticketPrice, address _vrfCoordinator, bytes32 _keyHash, uint64 _subscriptionId)
        VRFConsumerBaseV2(_vrfCoordinator)
        Ownable(msg.sender)
    {
        TICKET_PRICE = _ticketPrice;
        VRF_COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        KEY_HASH = _keyHash;
        SUBSCRIPTION_ID = _subscriptionId;
        currentPhase = Phase.Open;
    }

    /**
     * @notice Allows a user to purchase a ticket by sending the exact TICKET_PRICE.
     * @dev Adds the buyer to the participants array and increases the prize pool.
     */
    function buyTicket() external payable {
        if (currentPhase != Phase.Open) revert InvalidPhase();
        if (msg.value != TICKET_PRICE) revert IncorrectPayment();

        participants.push(msg.sender);
        prizePool += msg.value;
        emit TicketPurchased(msg.sender);
    }

    /**
     * @notice Locks the lottery and requests a random number from the Chainlink Oracle.
     * @dev Replaces the traditional closeSale() and commitHash() functions.
     * @return requestId The unique identifier for the VRF request.
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
     * @notice The callback function executed by the Chainlink Oracle to deliver randomness.
     * @dev Determines the winner using modulo arithmetic against the participants array length.
     * @param randomWords The array of random numbers provided by the oracle.
     */
    function fulfillRandomWords(
        uint256,
        /* requestId */
        uint256[] memory randomWords
    )
        internal
        override
    {
        if (currentPhase != Phase.Calculating) return;

        uint256 winnerIndex = randomWords[0] % participants.length;
        winner = participants[winnerIndex];
        currentPhase = Phase.Drawn;

        emit WinnerDrawn(winner);
    }

    /**
     * @notice Allows the designated winner to withdraw the entire prize pool.
     * @dev Implements the Checks-Effects-Interactions (CEI) pattern and ReentrancyGuard.
     */
    function claimPrize() external nonReentrant {
        if (currentPhase != Phase.Drawn) revert InvalidPhase();
        if (msg.sender != winner) revert NotWinner();

        uint256 amount = prizePool;
        prizePool = 0; // CEI pattern

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }
}
