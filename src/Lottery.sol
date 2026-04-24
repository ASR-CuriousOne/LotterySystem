// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Decentralized Lottery with Commit-Reveal
 * @notice Implements a secure, verifiable lottery using a commit-reveal randomness scheme.
 * @dev Inherits from OpenZeppelin's Ownable for access control and ReentrancyGuard for withdrawal safety.
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
    uint256 public immutable TICKET_PRICE;
    uint256 public prizePool;
    bytes32 public committedHash;
    address public winner;

    // --- Extended Optimizations ---
    uint256 public ticketBitmap; // Bits 0-255 track ticket availability
    uint16 public ticketsSold;
    mapping(uint8 => address) public ticketOwners;
    mapping(address => uint256) public pendingWithdrawals; // Pull-Over-Push Vault

    // --- Custom Errors ---
    error Lottery__InvalidPhase(LotteryPhase expected, LotteryPhase actual);
    error Lottery__IncorrectTicketPrice(uint256 expected, uint256 provided);
    error Lottery__HashMismatch();
    error Lottery__NotWinner(address caller);
    error Lottery__TransferFailed();
    error Lottery__NoParticipants();
    error Lottery__TicketAlreadySold();
    error Lottery__SoldOut();
    error Lottery__NoFundsToWithdraw();

    // --- Events ---
    event TicketPurchased(address indexed buyer, uint8 ticketIndex);
    event SaleClosed();
    event HashCommitted(bytes32 _hash);
    event WinnerDrawn(address indexed winner, uint256 amount);
    event PrizeClaimed(address indexed winner, uint256 amount);

    /**
     * @notice Initializes the lottery with a specific ticket price.
     * @param initialTicketPrice The cost to buy a single ticket in wei.
     */
    constructor(uint256 initialTicketPrice) Ownable(msg.sender) {
        TICKET_PRICE = initialTicketPrice;
        currentPhase = LotteryPhase.Open;
    }

    // --- Core Logic ---

    /**
     * @notice Allows a user to purchase a specific ticket number between 0 and 255.
     * @dev Reverts if the phase is not Open, if the exact ticket price is not sent, or if the ticket is claimed.
     * @param ticketIndex The chosen ticket number (0-255).
     */
    function buyTicket(uint8 ticketIndex) external payable {
        if (currentPhase != LotteryPhase.Open) revert Lottery__InvalidPhase(LotteryPhase.Open, currentPhase);
        if (msg.value != TICKET_PRICE) revert Lottery__IncorrectTicketPrice(TICKET_PRICE, msg.value);

        // Bitwise check to ensure the ticket isn't already sold
        if ((ticketBitmap & (uint256(1) << ticketIndex)) != 0) revert Lottery__TicketAlreadySold();

        // Mark ticket as sold
        ticketBitmap |= (uint256(1) << ticketIndex);
        ticketsSold += 1;
        prizePool += msg.value;
        ticketOwners[ticketIndex] = msg.sender;

        emit TicketPurchased(msg.sender, ticketIndex);
    }

    /**
     * @notice Allows a user to purchase the next available ticket automatically.
     * @dev Overloaded function to maintain compatibility with existing tests and simple frontends.
     */
    function buyTicket() external payable {
        if (currentPhase != LotteryPhase.Open) revert Lottery__InvalidPhase(LotteryPhase.Open, currentPhase);
        if (msg.value != TICKET_PRICE) revert Lottery__IncorrectTicketPrice(TICKET_PRICE, msg.value);
        if (ticketsSold >= 256) revert Lottery__SoldOut();

        // Find the lowest available ticket index
        uint8 ticketIndex = 0;
        uint256 tempMap = ticketBitmap;
        while ((tempMap & 1) == 1) {
            ticketIndex++;
            tempMap >>= 1;
        }

        ticketBitmap |= (uint256(1) << ticketIndex);
        ticketsSold += 1;
        prizePool += msg.value;
        ticketOwners[ticketIndex] = msg.sender;

        emit TicketPurchased(msg.sender, ticketIndex);
    }

    /**
     * @notice Closes the ticket sale phase, preventing further purchases.
     * @dev Only callable by contract owner. Reverts if no participants have joined.
     */
    function closeSale() external onlyOwner {
        if (currentPhase != LotteryPhase.Open) revert Lottery__InvalidPhase(LotteryPhase.Open, currentPhase);
        if (ticketsSold == 0) revert Lottery__NoParticipants();

        currentPhase = LotteryPhase.SaleClosed;
        emit SaleClosed();
    }

    /**
     * @notice Owner commits the hashed secret.
     * @dev Only callable by owner. Transitions the state to the Committed phase.
     * @param _hash The keccak256 hash of the secret string.
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
     * @notice Owner reveals the secret to draw the winner deterministically.
     * @dev Verifies the secret against the committedHash. Calculates the winner using the bitmap and transitions to Drawn.
     * @param _secret The raw string or bytes that was previously hashed.
     */
    function revealAndDraw(bytes32 _secret) external onlyOwner {
        if (currentPhase != LotteryPhase.Committed) revert Lottery__InvalidPhase(LotteryPhase.Committed, currentPhase);

        // Verify the hash matches the commitment
        if (keccak256(abi.encodePacked(_secret)) != committedHash) revert Lottery__HashMismatch();

        // Calculate base winner index using the assignment's deterministic formula
        uint256 winningIndex = uint256(keccak256(abi.encodePacked(_secret, block.number))) % 256;
        uint256 bitmap = ticketBitmap;

        // If the formula picks an unsold ticket, deterministically roll over to the next sold one.
        // Guaranteed to terminate because closeSale() requires ticketsSold > 0.
        while ((bitmap & (uint256(1) << winningIndex)) == 0) {
            winningIndex = (winningIndex + 1) % 256;
        }

        // casting to 'uint8' is safe because winningIndex is strictly bounded between 0 and 255 via modulo 256 arithmetic
        // forge-lint: disable-next-line(unsafe-typecast)
        winner = ticketOwners[uint8(winningIndex)];
        currentPhase = LotteryPhase.Drawn;

        // Pull-Over-Push: Route funds to the vault
        pendingWithdrawals[winner] += prizePool;

        emit WinnerDrawn(winner, prizePool);
    }

    /**
     * @notice Allows the winner to withdraw the prize pool from their vault.
     * @dev Applies nonReentrant modifier. Reverts if the caller is not the recorded winner or vault is empty.
     */
    function claimPrize() external nonReentrant {
        if (currentPhase != LotteryPhase.Drawn) revert Lottery__InvalidPhase(LotteryPhase.Drawn, currentPhase);
        if (msg.sender != winner) revert Lottery__NotWinner(msg.sender);

        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert Lottery__NoFundsToWithdraw();

        pendingWithdrawals[msg.sender] = 0; // CEI Pattern
        prizePool = 0; // Reset pool state

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert Lottery__TransferFailed();

        emit PrizeClaimed(msg.sender, amount);
    }

    /**
     * @notice Returns comprehensive data about the current lottery state.
     * @return phase The current phase of the lottery.
     * @return price The exact cost of a single ticket.
     * @return participantCount The total number of tickets sold.
     * @return pool The total accumulated prize pool in wei.
     * @return winningAddress The address of the winner (address(0) if not yet drawn).
     */
    function getLotteryInfo()
        external
        view
        returns (LotteryPhase phase, uint256 price, uint256 participantCount, uint256 pool, address winningAddress)
    {
        return (currentPhase, TICKET_PRICE, uint256(ticketsSold), prizePool, winner);
    }
}
