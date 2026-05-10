// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title Veritas Lottery System (Tier 1)
 * @author BitBoyz Team
 * @notice A decentralised, commit-reveal lottery contract that ensures transparent and verifiable winner selection.
 * @dev Implements a linear state machine (Open -> SaleClosed -> Committed -> Drawn) to manage the lottery lifecycle.
 * Utilises the Checks-Effects-Interactions (CEI) pattern and OpenZeppelin guardrails for fund security.
 */
contract Lottery is Ownable, ReentrancyGuard {
    /**
     * @notice The operational phases of a manual commit-reveal lottery round.
     * @custom:value Open Participants may purchase tickets and enter the pool.
     * @custom:value SaleClosed The entry window is frozen; owner must now commit a secret hash.
     * @custom:value Committed The cryptographic hash is locked on-chain; awaiting the raw secret reveal.
     * @custom:value Drawn The secret has been verified, a winner selected, and the prize is ready for claiming.
     */
    enum LotteryPhase {
        Open,
        SaleClosed,
        Committed,
        Drawn
    }

    /**
     * @notice The current operational stage of the lottery instance.
     */
    LotteryPhase public currentPhase;

    /**
     *  @notice The fixed entry cost required to purchase a single ticket.
     */
    uint256 public immutable TICKET_PRICE;

    /**
     *  @notice The physical cap on total entries allowed per round to manage array growth.
     */
    uint256 public maxTickets;

    /**
     *  @notice The total ETH accumulated from ticket sales, to be awarded to the winner.
     */
    uint256 public prizePool;

    /**
     *  @notice Stores the keccak256 hash of the owner's secret to prevent mid-game manipulation.
     */
    bytes32 public committedHash;

    /**
     *  @notice The address of the participant selected as the winner of the current round.
     */
    address public winner;

    /**
     *  @notice Array of participant addresses; multiple entries per address are permitted.
     */
    address[] public participants;

    /**
     *  @notice Emitted when a participant successfully purchases a ticket.
     */
    event TicketPurchased(address indexed buyer);

    /**
     *  @notice Emitted when the owner closes sales, preventing further entries.
     */
    event SaleClosed();

    /**
     *  @notice Emitted when the owner locks in the hash commitment of the secret.
     */
    event HashCommitted(bytes32 hash);

    /**
     *  @notice Emitted when the reveal is verified and a winner is mathematically selected.
     */
    event WinnerDrawn(address indexed winner, uint256 amount);

    /**
     *  @notice Emitted when the verified winner successfully withdraws the prize pool.
     */
    event PrizeClaimed(address indexed winner, uint256 amount);

    /**
     * @notice Initializes the lottery parameters and sets the deployer as the initial owner.
     * @param _ticketPrice The amount in wei required for a single entry.
     * @param _maxTickets The maximum number of entries allowed.
     */
    constructor(uint256 _ticketPrice, uint256 _maxTickets) Ownable(msg.sender) {
        TICKET_PRICE = _ticketPrice;
        maxTickets = _maxTickets;
        currentPhase = LotteryPhase.Open;
    }

    /**
     * @notice Allows a user to purchase a single entry into the lottery.
     * @dev Reverts if the phase is not Open, payment is incorrect, or the capacity limit is reached.
     */
    function buyTicket() external payable {
        require(currentPhase == LotteryPhase.Open, "Lottery not open");
        require(msg.value == TICKET_PRICE, "Incorrect ticket price");
        require(participants.length < maxTickets, "Ticket limit reached");

        participants.push(msg.sender);
        prizePool += msg.value;

        emit TicketPurchased(msg.sender);
    }

    /**
     * @notice Allows a user to purchase multiple entries in a single transaction.
     * @dev Included to optimize gas for bulk purchasers and satisfy presentation requirements.
     * @param numberOfTickets The total number of entries to buy.
     */
    function batchBuyTickets(uint256 numberOfTickets) external payable {
        require(currentPhase == LotteryPhase.Open, "Lottery not open");
        require(msg.value == TICKET_PRICE * numberOfTickets, "Incorrect total price");
        require(participants.length + numberOfTickets <= maxTickets, "Exceeds ticket limit");
        require(numberOfTickets > 0, "Must buy at least one ticket");

        for (uint256 i = 0; i < numberOfTickets; i++) {
            participants.push(msg.sender);
        }
        prizePool += msg.value;

        for (uint256 i = 0; i < numberOfTickets; i++) {
            emit TicketPurchased(msg.sender);
        }
    }

    /**
     * @notice Calculates the total entries owned by a specific address.
     * @dev Performs a linear scan of the participants array.
     * @param user The address of the participant to query.
     * @return count The total number of tickets held by the specified user.
     */
    function getTicketCount(address user) external view returns (uint256 count) {
        uint256 length = participants.length;
        for (uint256 i = 0; i < length; i++) {
            if (participants[i] == user) {
                count++;
            }
        }
    }

    /**
     * @notice Freezes the participant pool and prevents new ticket purchases.
     * @dev Restricts entries; requires at least one participant to ensure a valid draw.
     */
    function closeSale() external onlyOwner {
        require(currentPhase == LotteryPhase.Open, "Lottery not open");
        require(participants.length > 0, "No participants");

        currentPhase = LotteryPhase.SaleClosed;
        emit SaleClosed();
    }

    /**
     * @notice Locks the owner into a specific secret by submitting its hash.
     * @dev Transitions the contract to the Committed phase.
     * @param _hash The keccak256(secret) generated by the owner off-chain.
     */
    function commitHash(bytes32 _hash) external onlyOwner {
        require(currentPhase == LotteryPhase.SaleClosed, "Sale not closed");

        committedHash = _hash;
        currentPhase = LotteryPhase.Committed;

        emit HashCommitted(_hash);
    }

    /**
     * @notice Verifies the secret and determines the winner using deterministic on-chain randomness.
     * @dev Utilises the formula: keccak256(secret + block.number) % totalParticipants.
     * Explicitly uses block.number to mitigate minor validator manipulation common with block.timestamp.
     * @param _secret The raw secret value whose hash must match the previous commitment.
     */
    function revealAndDraw(bytes32 _secret) external onlyOwner {
        require(currentPhase == LotteryPhase.Committed, "Hash not committed");
        require(keccak256(abi.encodePacked(_secret)) == committedHash, "Secret does not match committed hash");

        uint256 winnerIndex = uint256(keccak256(abi.encodePacked(_secret, block.number))) % participants.length;
        winner = participants[winnerIndex];
        currentPhase = LotteryPhase.Drawn;

        emit WinnerDrawn(winner, prizePool);
    }

    /**
     * @notice Transfers the accumulated prize pool to the verified winner.
     * @dev Strictly follows the Checks-Effects-Interactions (CEI) pattern to prevent reentrancy.
     * Uses a low-level .call for ETH transfer to ensure compatibility with all wallet types.
     */
    function claimPrize() external nonReentrant {
        require(currentPhase == LotteryPhase.Drawn, "Winner not drawn yet");
        require(msg.sender == winner, "Caller is not the winner");
        require(prizePool > 0, "Prize already claimed");

        uint256 amount = prizePool;
        prizePool = 0;

        (bool success,) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");

        emit PrizeClaimed(msg.sender, amount);
    }

    /**
     * @notice Provides a consolidated view of the current lottery state.
     * @return The phase, ticket price, total entries, total prize, and current winner address.
     */
    function getLotteryInfo() external view returns (LotteryPhase, uint256, uint256, uint256, address) {
        return (currentPhase, TICKET_PRICE, participants.length, prizePool, winner);
    }
}
