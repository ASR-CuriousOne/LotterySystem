// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";
import {console2} from "forge-std/Test.sol";

/**
 * @title Advanced Threat Simulation (Attacker Bots)
 * @notice Simulates real-world attack vectors including Miner MEV, Owner DoS, and Reentrancy.
 */
contract AttackerBotsTest is BaseLotteryTest {
    GreedyReentrantBot public reentrancyBot;

    function setUp() public override {
        super.setUp();
        reentrancyBot = new GreedyReentrantBot(lottery);
        vm.deal(address(reentrancyBot), 1 ether);
    }

    /**
     * @notice Simulates an owner trying to change the commit hash after seeing the
     * ticket sales, or trying to bypass the lock-in phase.
     */
    function testBot_OwnerCannotTamperWithCommitment() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        bytes32 fakeHash = keccak256(abi.encodePacked("fakeSecret"));

        vm.prank(owner);
        lottery.commitHash(committedHash);

        // ATTACK: Owner tries to overwrite the hash to change the outcome
        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.SaleClosed, Lottery.LotteryPhase.Committed
            )
        );
        vm.prank(owner);
        lottery.commitHash(fakeHash);
    }

    /**
     * @notice PROVES THE "RESIDUAL TRUST" FLAW: If the owner buys a ticket and
     * computes that they will lose, they can simply refuse to reveal the secret,
     * trapping everyone's funds forever.
     */
    function testBot_OwnerCanDenyServiceByWithholdingSecret() public {
        vm.deal(owner, 1 ether);

        // Player 1 buys
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        // Owner buys a ticket (acting as a player)
        vm.prank(owner);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        // At this point, the phase is 'Committed'.
        // The owner calculates off-chain: keccak256(SECRET + block.number) % 2.
        // If the result == 0 (Player 1 wins), the malicious owner simply stops interacting.
        // Assert that nobody else can force the draw or refund.

        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.Drawn, Lottery.LotteryPhase.Committed
            )
        );
        vm.prank(player1);
        lottery.claimPrize();

        console2.log("Vulnerability Proven: Owner can hold funds hostage by never calling revealAndDraw()");
    }

    /**
     * @notice Simulates a malicious Validator intercepting the owner's reveal transaction
     * in the mempool and holding it until a favorable block.number arrives.
     */
    function testBot_MinerBlockManipulation() public {
        address minerAttacker = makeAddr("minerAttacker");
        vm.deal(minerAttacker, 1 ether);

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(minerAttacker);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        // ATTACK: The owner broadcasts `revealAndDraw(SECRET)`.
        // The malicious miner sees the SECRET in the public mempool.
        // The miner simulates future blocks to find which one makes them the winner.

        uint256 currentBlock = block.number;
        uint256 favorableBlock = currentBlock;

        // Miner runs this loop off-chain in their node software
        for (uint256 i = 0; i < 20; i++) {
            uint256 simulatedWinnerIndex = uint256(keccak256(abi.encodePacked(SECRET, currentBlock + i))) % 2;
            if (simulatedWinnerIndex == 1) {
                // Index 1 is the minerAttacker
                favorableBlock = currentBlock + i;
                break;
            }
        }

        // Miner intentionally delays including the transaction until the favorable block
        vm.roll(favorableBlock);

        // Miner finally includes the owner's transaction
        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        // Prove the miner successfully manipulated the block outcome to win
        assertEq(lottery.winner(), minerAttacker);
        console2.log("MEV Attack Successful: Miner manipulated block.number to force a win at block", favorableBlock);
    }

    /**
     * @notice Verifies that a malicious smart contract cannot drain the prize pool
     * by re-entering the claimPrize function during the ETH transfer.
     */
    function testBot_GreedyReentrancyAttempt() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        reentrancyBot.buyTicket();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        // Force the bot to win by rolling to a block that favors index 1
        uint256 targetBlock = block.number;
        while (uint256(keccak256(abi.encodePacked(SECRET, targetBlock))) % 2 != 1) {
            targetBlock++;
        }
        vm.roll(targetBlock);

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        assertEq(lottery.winner(), address(reentrancyBot));

        // Attempt to drain. The ReentrancyGuard should catch this and revert the transaction.
        vm.expectRevert();
        reentrancyBot.claim();

        console2.log("Reentrancy Blocked: Greedy contract failed to drain the pool.");
    }
}

/**
 * @notice A malicious contract designed to exploit state changes by re-entering
 * the target contract during ETH fallbacks.
 */
contract GreedyReentrantBot {
    Lottery public target;
    uint256 public attackCount;

    constructor(Lottery _target) {
        target = _target;
    }

    function buyTicket() external {
        target.buyTicket{value: 0.01 ether}();
    }

    function claim() external {
        target.claimPrize();
    }

    // The malicious payload: triggers automatically when receiving ETH
    receive() external payable {
        // Attack exactly once to trigger the ReentrancyGuard
        if (attackCount == 0) {
            attackCount++;
            // Re-enter the contract before it finishes updating its state
            target.claimPrize();
        }
    }
}
