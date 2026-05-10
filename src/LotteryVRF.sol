// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {VRFConsumerBaseV2} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {
    VRFCoordinatorV2Interface
} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";

/**
 * @title Veritas VRF-Powered Lottery (Tier 2)
 * @author BitBoyz Team
 * @notice A lottery implementation that utilizes Chainlink VRF for provably fair, tamper-proof randomness.
 * @dev Inherits from VRFConsumerBaseV2, Ownable, and ReentrancyGuard.
 * This architecture replaces the manual owner-led commit-reveal process with a decentralized oracle request-response loop.
 */
contract LotteryVRF is VRFConsumerBaseV2, Ownable, ReentrancyGuard {
    /**
     * @notice Operational phases of the VRF-powered lottery.
     * @custom:value Open Tickets can be purchased by participants.
     * @custom:value Calculating Awaiting randomness fulfillment from the oracle network.
     * @custom:value Drawn The winner has been selected and funds are ready for claiming.
     */
    enum Phase {
        Open,
        Calculating,
        Drawn
    }

    /**
     * @notice The current operational state of the lottery instance.
     */
    Phase public currentPhase;

    /**
     *  @notice The immutable cost in wei to purchase one entry.
     */
    uint256 public immutable TICKET_PRICE;

    /**
     *  @notice The total ETH accumulated for the current round's prize.
     */
    uint256 public prizePool;

    /**
     *  @notice The address of the participant selected by the VRF callback.
     */
    address public winner;

    /**
     *  @notice The dynamic list of participant addresses for the current round.
     */
    address[] public participants;

    /**
     *  @notice Interface for interacting with the Chainlink VRF Coordinator.
     */
    VRFCoordinatorV2Interface public immutable VRF_COORDINATOR;

    /**
     *  @notice The gas lane key hash used to set the price for a randomness request.
     */
    bytes32 public immutable KEY_HASH;

    /**
     *  @notice The unique ID of the funded Chainlink subscription used to pay for requests.
     */
    uint64 public immutable SUBSCRIPTION_ID;

    /**
     *  @notice The number of block confirmations the oracle waits before responding to protect against reorgs.
     */
    uint16 public constant REQUEST_CONFIRMATIONS = 3;

    /**
     *  @notice The maximum amount of gas permitted for the oracle to spend executing the callback function.
     */
    uint32 public constant CALLBACK_GAS_LIMIT = 100000;

    /**
     *  @notice The specific quantity of random values requested from the Chainlink VRF per draw.
     */
    uint32 public constant NUM_WORDS = 1;

    /**
     * @notice Thrown when a function is called outside its permitted lifecycle phase.
     */
    error InvalidPhase();

    /**
     *  @notice Thrown when the sent ETH does not exactly match the TICKET_PRICE. [cite: 136]
     */
    error IncorrectPayment();

    /**
     *  @notice Thrown if an address other than the selected winner attempts to claim the prize. [cite: 8]
     */
    error NotWinner();

    /**
     *  @notice Thrown when the native ETH transfer to the winner fails. [cite: 24]
     */
    error TransferFailed();

    /**
     *  @notice Emitted when a participant enters the lottery round.
     */
    event TicketPurchased(address indexed buyer);

    /**
     *  @notice Emitted when the owner triggers the randomness request to the Chainlink network.
     */
    event RandomnessRequested(uint256 requestId);

    /**
     *  @notice Emitted when the oracle delivers the randomness and a winner is selected.
     */
    event WinnerDrawn(address indexed winner);

    /**
     * @notice Configures the contract with the necessary Chainlink VRF parameters and ticket pricing.
     * @param _ticketPrice The cost of a single entry in wei.
     * @param _vrfCoordinator The address of the decentralized oracle coordinator.
     * @param _keyHash The network-specific gas lane identifier.
     * @param _subscriptionId The funded subscription ID for VRF fee billing.
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
     * @notice Allows a user to enter the lottery by providing the exact payment.
     * @dev Reverts if the phase is not Open or the payment is incorrect.
     * Appends the caller's address to the participants array. [cite: 138]
     */
    function buyTicket() external payable {
        if (currentPhase != Phase.Open) revert InvalidPhase();
        if (msg.value != TICKET_PRICE) revert IncorrectPayment();

        participants.push(msg.sender);
        prizePool += msg.value;
        emit TicketPurchased(msg.sender);
    }

    /**
     * @notice Closes ticket sales and initiates the request for provable randomness.
     * @dev Restricted to the contract owner. Transitions the state to 'Calculating'. [cite: 276, 277]
     * @return requestId The unique identifier generated by the VRF Coordinator.
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
     * @notice Asynchronous callback executed by the Chainlink Oracle to deliver verified randomness.
     * @dev Uses modulo arithmetic against the participants list to select a winner. [cite: 280]
     * Transitions the contract to the 'Drawn' phase upon successful selection.
     * @param randomWords The cryptographically verified random data provided by the oracle.
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
     * @notice Facilitates the withdrawal of the prize pool by the verified winner.
     * @dev Strictly enforces the Checks-Effects-Interactions (CEI) pattern to mitigate reentrancy. [cite: 168, 185]
     * Zeroes the prizePool in storage before executing the native ETH transfer. [cite: 186]
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
