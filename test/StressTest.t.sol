// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Lottery Security and Stress Tests
 * @notice Validates ETH accounting under heavy load, edge-case values, and secure prize distribution.
 */
contract LotterySecurityTest is BaseLotteryTest {
    
    /**
     * @notice Stress tests the system with a massive number of concurrent buyers.
     * @dev Simulates 1,000 distinct addresses buying tickets and verifies exact ETH accounting.
     */
    function test_MassiveConcurrentBuyers() public {
        uint160 numBuyers = 1000;
        uint256 initialBalance = address(lottery).balance;
        
        for(uint160 i = 1; i <= numBuyers; i++) {
            // Generate a unique address (offsetting by 100 to avoid colliding with player1/player2 from Base)
            address user = address(i + 100); 
            
            // Give the user exact funds and prank the next call
            hoax(user, TICKET_PRICE);
            lottery.buyTicket{value: TICKET_PRICE}();
        }

        // Verify that the contract's balance increased by exactly the amount sold
        uint256 expectedBalance = initialBalance + (TICKET_PRICE * numBuyers);
        assertEq(address(lottery).balance, expectedBalance, "ETH accounting mismatch after massive load");
    }

    /**
     * @notice Fuzz tests ticket purchasing with random, excessive ETH amounts.
     * @dev Ensures the contract rejects payments that exceed the exact ticket price.
     * @param amount The randomized amount of ETH sent to the contract.
     */
    function testFuzz_RevertIfOverpayment(uint256 amount) public {
        // Assume the randomized amount is strictly greater than the ticket price
        vm.assume(amount > TICKET_PRICE && amount < 100_000_000 ether);
        
        address whale = address(0x999);
        hoax(whale, amount);

        // Updated to match your exact custom error and its required parameters
        vm.expectRevert(
            abi.encodeWithSelector(Lottery.Lottery__IncorrectTicketPrice.selector, TICKET_PRICE, amount)
        );
        lottery.buyTicket{value: amount}();
    }

    /**
     * @notice Ensures only the chosen winner can claim the prize, and only exactly once.
     * @dev Tests unauthorized claim attempts, successful claims, and double-claim prevention.
     */
    function test_SecurePrizeClaiming() public {
        // 1. Players buy tickets
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();
        
        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 2. Owner closes the sale and draws the winner using Commit-Reveal
        bytes32 secret = bytes32("random_secret_string");
        bytes32 commitHash = keccak256(abi.encodePacked(secret));

        vm.startPrank(owner);
        lottery.closeSale();
        lottery.commitHash(commitHash);
        lottery.revealAndDraw(secret);
        vm.stopPrank();

        // Find out who actually won based on the block hash math in your contract
        address actualWinner = lottery.winner();
        address attacker = (actualWinner == player1) ? player2 : player1;

        // 3. Attacker attempts to steal the prize
        vm.prank(attacker);
        // Updated to match your exact unauthorized claim error
        vm.expectRevert(
            abi.encodeWithSelector(Lottery.Lottery__NotWinner.selector, attacker)
        );
        lottery.claimPrize();

        // 4. Actual winner claims successfully
        uint256 winnerBalanceBefore = actualWinner.balance;
        uint256 expectedPrize = lottery.prizePool();
        
        vm.prank(actualWinner);
        lottery.claimPrize();

        assertEq(actualWinner.balance, winnerBalanceBefore + expectedPrize, "Winner did not receive exact funds");

        // 5. Winner attempts to drain the contract again by double-claiming
        // Note: Your contract sets prizePool = 0 instead of reverting. 
        // We verify that calling it again sends exactly 0 ETH.
        vm.prank(actualWinner);
        lottery.claimPrize();
        assertEq(actualWinner.balance, winnerBalanceBefore + expectedPrize, "Double claim should yield 0 extra ETH");
    }

    /**
     * @notice Stateful invariant test to guarantee ETH backing.
     * @dev The contract balance must always be greater than or equal to the collected ticket revenue, 
     * unless the prize has been actively claimed.
     */
    function invariant_ContractBalanceNeverBreaks() public view {
        // Updated to use your getLotteryInfo() getter to fetch participant count
        (, , uint256 participantCount, , ) = lottery.getLotteryInfo();
        uint256 expectedMinimumBalance = participantCount * TICKET_PRICE;
        
        // Your contract doesn't have a "Claimed" phase. 
        // It keeps the phase as "Drawn" but sets prizePool to 0.
        if (lottery.prizePool() > 0) {
            assertGe(address(lottery).balance, expectedMinimumBalance, "CRITICAL: Contract is undercollateralized");
        }
    }
}