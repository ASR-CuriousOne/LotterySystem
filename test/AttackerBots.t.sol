// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";
import {console2} from "forge-std/Test.sol";

/**
 * @title Advanced Threat Simulation (Attacker Bots)
 * @notice Simulates real-world attack vectors including Miner MEV, Owner DoS, and Reentrancy.
 * @dev Inherits from BaseLotteryTest to utilize the standard testing state and accounts.
 */
contract AttackerBotsTest is BaseLotteryTest {
    /// @notice The instance of the malicious reentrancy bot used for testing
    GreedyReentrantBot public reentrancyBot;

    /**
     * @notice Initializes the test environment and funds the attacker bot.
     * @dev Overrides the BaseLotteryTest setUp function.
     */
    function setUp() public override {
        super.setUp();
        reentrancyBot = new GreedyReentrantBot(lottery);
        vm.deal(address(reentrancyBot), 1 ether);
    }

    /**
     * @notice Simulates an owner attempting to overwrite the commit hash after seeing ticket sales.
     * @dev Validates that the state machine strictly prevents re-committing hashes to alter outcomes.
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
     * @notice Proves the "Residual Trust" flaw of the commit-reveal scheme.
     * @dev Demonstrates that if the owner participates and realizes they will lose, they can withhold the reveal transaction to permanently lock funds.
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
     * @notice Simulates a malicious Validator (Miner) executing an MEV attack via block manipulation.
     * @dev The attacker scans the mempool, computes favorable block outcomes off-chain, and delays the transaction inclusion until they are guaranteed to win.
     */
    function testBot_MinerBlockManipulation() public {
        address minerAttacker = makeAddr("minerAttacker");
        vm.deal(minerAttacker, 1 ether);

        // 1. Normal player buys Ticket 0
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 2. Miner buys Ticket 1
        vm.prank(minerAttacker);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 3. Owner closes the sale and commits the hash
        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        // 4. MEV ATTACK: Miner simulates future blocks until it finds one where it wins
        uint256 i = 0;
        while (true) {
            // Simulate the exact math from the contract
            uint256 winningIndex = uint256(keccak256(abi.encodePacked(SECRET, block.number + i))) % 256;
            uint256 bitmap = lottery.ticketBitmap();

            // Simulate the rollover math
            while ((bitmap & (uint256(1) << winningIndex)) == 0) {
                winningIndex = (winningIndex + 1) % 256;
            }

            // If the simulated winner is the miner, force the blockchain to this exact block!
            // casting to 'uint8' is safe because winningIndex is strictly bounded between 0 and 255 via modulo 256 arithmetic
            // forge-lint: disable-next-line(unsafe-typecast)
            if (lottery.ticketOwners(uint8(winningIndex)) == minerAttacker) {
                vm.roll(block.number + i);
                break;
            }
            i++;
        }

        // 5. Owner blindly reveals, unknowingly falling into the miner's trap
        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        // 6. Prove the miner successfully manipulated the outcome
        assertEq(lottery.winner(), minerAttacker, "Miner MEV Attack Failed!");
        console2.log("MEV Attack Successful: Miner manipulated block.number to force a win");
    }

    /**
     * @notice Verifies that the ReentrancyGuard successfully blocks a malicious smart contract from draining the prize pool.
     * @dev Forces the bot to win, then allows its fallback function to maliciously re-enter the claimPrize function.
     */
    function testBot_GreedyReentrancyAttempt() public {
        reentrancyBot.buyTicket();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);
        vm.roll(block.number + 1);

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
 * @title Greedy Reentrant Bot
 * @notice A malicious contract designed to exploit state changes via recursive ETH fallback calls.
 */
contract GreedyReentrantBot {
    /// @notice The target lottery contract to attack
    Lottery public target;

    /// @notice Tracks the number of reentrancy attempts to prevent infinite gas loops
    uint256 public attackCount;

    /**
     * @notice Initializes the attacker bot with the target contract.
     * @param _target The address of the vulnerable lottery contract.
     */
    constructor(Lottery _target) {
        target = _target;
    }

    /**
     * @notice Initiates the attack by purchasing a ticket.
     */
    function buyTicket() external {
        target.buyTicket{value: 0.01 ether}();
    }

    /**
     * @notice Triggers the initial, legitimate prize claim.
     */
    function claim() external {
        target.claimPrize();
    }

    /**
     * @notice The malicious payload that automatically triggers when receiving ETH.
     * @dev Attempts to re-enter the claimPrize function before the target updates its state.
     */
    receive() external payable {
        // Attack exactly once to trigger the ReentrancyGuard
        if (attackCount == 0) {
            attackCount++;
            // Re-enter the contract before it finishes updating its state
            target.claimPrize();
        }
    }
}
