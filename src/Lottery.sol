// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Decentralized Lottery with Commit-Reveal
 * @notice Implements a secure, verifiable lottery using a commit-reveal randomness scheme.
 */
contract Lottery is Ownable, ReentrancyGuard {
    // --- Enums & Structs ---
    enum LotteryPhase {
        Open,
        SaleClosed,
        Committed,
        Drawn
    }

    // --- State Variables ---
    LotteryPhase public currentPhase;
    uint256 public immutable ticketPrice;
    uint256 public prizePool;
    bytes32 public committedHash;
    address public winner;
    address[] public participants;

    // --- Custom Errors ---
    error Lottery__InvalidPhase(LotteryPhase expected, LotteryPhase actual);
    error Lottery__IncorrectTicketPrice(uint256 expected, uint256 provided);
    error Lottery__HashMismatch();
    error Lottery__NotWinner(address caller);
    error Lottery__TransferFailed();
    error Lottery__NoParticipants();

    // --- Events ---
    event TicketPurchased(address indexed buyer);
    event SaleClosed();
    event HashCommitted(bytes32 _hash);
    event WinnerDrawn(address indexed winner);
    event PrizeClaimed(address indexed winner, uint256 amount);

    /**
     * @notice Initializes the lottery with a specific ticket price
     * @param _ticketPrice The cost to buy a single ticket in wei
     */
    constructor(uint256 _ticketPrice) Ownable(msg.sender) {
        ticketPrice = _ticketPrice;
        currentPhase = LotteryPhase.Open;
    }

    // --- Core Logic ---

    /**
     * @notice Allows a user to purchase a ticket
     */
    function buyTicket() external payable {
        if (currentPhase != LotteryPhase.Open) revert Lottery__InvalidPhase(LotteryPhase.Open, currentPhase);
        if (msg.value != ticketPrice) revert Lottery__IncorrectTicketPrice(ticketPrice, msg.value);

        participants.push(msg.sender);
        prizePool += msg.value;

        emit TicketPurchased(msg.sender);
    }

    /**
     * @notice Closes the ticket sale phase.
     */
    function closeSale() external onlyOwner {
        if (currentPhase != LotteryPhase.Open) revert Lottery__InvalidPhase(LotteryPhase.Open, currentPhase);
        if (participants.length == 0) revert Lottery__NoParticipants();

        currentPhase = LotteryPhase.SaleClosed;
        emit SaleClosed();
    }

    /**
     * @notice Owner commits the hashed secret
     * @param _hash The keccak256 hash of the secret string
     */
    function commitHash(bytes32 _hash) external onlyOwner {
        if (currentPhase != LotteryPhase.SaleClosed) {
            revert Lottery__InvalidPhase(LotteryPhase.SaleClosed, currentPhase);
        }

        committedHash = _hash;
        currentPhase = LotteryPhase.Committed;

        emit HashCommitted(_hash);
    }

    /**
     * @notice Owner reveals the secret to draw the winner deterministically
     * @param _secret The raw string/bytes that was previously hashed
     */
    function revealAndDraw(bytes32 _secret) external onlyOwner {
        if (currentPhase != LotteryPhase.Committed) revert Lottery__InvalidPhase(LotteryPhase.Committed, currentPhase);

        // Verify the hash matches the commitment
        if (keccak256(abi.encodePacked(_secret)) != committedHash) revert Lottery__HashMismatch();

        // Calculate winner using the assignment's deterministic formula
        uint256 winnerIndex = uint256(keccak256(abi.encodePacked(_secret, block.number))) % participants.length;
        winner = participants[winnerIndex];
        currentPhase = LotteryPhase.Drawn;

        emit WinnerDrawn(winner);
    }

    /**
     * @notice Allows the winner to withdraw the prize pool
     */
    function claimPrize() external nonReentrant {
        if (currentPhase != LotteryPhase.Drawn) revert Lottery__InvalidPhase(LotteryPhase.Drawn, currentPhase);
        if (msg.sender != winner) revert Lottery__NotWinner(msg.sender);

        uint256 amount = prizePool;
        prizePool = 0; // Prevent further claims

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert Lottery__TransferFailed();

        emit PrizeClaimed(msg.sender, amount);
    }

    /**
     * @notice Returns comprehensive data about the current lottery state
     */
    function getLotteryInfo() external view returns (LotteryPhase, uint256, uint256, uint256, address) {
        return (currentPhase, ticketPrice, participants.length, prizePool, winner);
    }
}
