// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract Lottery is Ownable, ReentrancyGuard {
    enum LotteryPhase {
        Open,
        SaleClosed,
        Committed,
        Drawn
    }

    LotteryPhase public currentPhase;
    uint256 public immutable TICKET_PRICE;
    uint256 public maxTickets;
    uint256 public prizePool;
    bytes32 public committedHash;
    address public winner;
    address[] public participants;

    event TicketPurchased(address indexed buyer);
    event SaleClosed();
    event HashCommitted(bytes32 hash);
    event WinnerDrawn(address indexed winner, uint256 amount);
    event PrizeClaimed(address indexed winner, uint256 amount);

    constructor(uint256 _ticketPrice, uint256 _maxTickets) Ownable(msg.sender) {
        TICKET_PRICE = _ticketPrice;
        maxTickets = _maxTickets;
        currentPhase = LotteryPhase.Open;
    }

    function buyTicket() external payable {
        require(currentPhase == LotteryPhase.Open, "Lottery not open");
        require(msg.value == TICKET_PRICE, "Incorrect ticket price");
        require(participants.length < maxTickets, "Ticket limit reached");

        participants.push(msg.sender);
        prizePool += msg.value;

        emit TicketPurchased(msg.sender);
    }

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

    function getTicketCount(address user) external view returns (uint256 count) {
        uint256 length = participants.length;
        for (uint256 i = 0; i < length; i++) {
            if (participants[i] == user) {
                count++;
            }
        }
    }

    function closeSale() external onlyOwner {
        require(currentPhase == LotteryPhase.Open, "Lottery not open");
        require(participants.length > 0, "No participants");

        currentPhase = LotteryPhase.SaleClosed;
        emit SaleClosed();
    }

    function commitHash(bytes32 _hash) external onlyOwner {
        require(currentPhase == LotteryPhase.SaleClosed, "Sale not closed");

        committedHash = _hash;
        currentPhase = LotteryPhase.Committed;

        emit HashCommitted(_hash);
    }

    function revealAndDraw(bytes32 _secret) external onlyOwner {
        require(currentPhase == LotteryPhase.Committed, "Hash not committed");
        require(keccak256(abi.encodePacked(_secret)) == committedHash, "Secret does not match committed hash");

        uint256 winnerIndex = uint256(keccak256(abi.encodePacked(_secret, block.number))) % participants.length;
        winner = participants[winnerIndex];
        currentPhase = LotteryPhase.Drawn;

        emit WinnerDrawn(winner, prizePool);
    }

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

    function getLotteryInfo() external view returns (LotteryPhase, uint256, uint256, uint256, address) {
        return (currentPhase, TICKET_PRICE, participants.length, prizePool, winner);
    }
}
