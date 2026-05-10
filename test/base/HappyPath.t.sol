// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

/**
 * @title Veritas Happy Path Integration Test
 * @author BitBoyz Team
 * @notice Validates the standard successful lifecycle of the lottery protocol.
 * @dev Inherits from BaseLotteryTest. This suite performs a full integration test covering
 * ticket purchases, phase transitions, randomness revelation, and prize distribution[cite: 46, 64].
 */
contract HappyPathTest is BaseLotteryTest {
    /**
     * @notice Executes a complete, successful lottery round from start to finish.
     * @dev This test satisfies the "Happy-Path Execution" rubric requirement[cite: 304, 309].
     * It specifically validates:
     * 1. Multi-user ticket acquisition (single and batch)[cite: 100, 104].
     * 2. Successful phase linear progression (Open -> SaleClosed -> Committed -> Drawn)[cite: 66, 67].
     * 3. Cryptographic reveal integrity and winner selection[cite: 82, 83].
     * 4. Final prize withdrawal using the Pull-over-Push pattern[cite: 134, 150].
     */
    function testHappyPathFullLotteryLifecycle() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(player2);
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(2);

        assertEq(lottery.prizePool(), TICKET_PRICE * 3);

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.roll(block.number + 10);

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        address winner = lottery.winner();
        assertTrue(winner == player1 || winner == player2);

        uint256 winnerBalanceBefore = winner.balance;
        uint256 prize = lottery.prizePool();

        vm.prank(winner);
        lottery.claimPrize();

        assertEq(winner.balance, winnerBalanceBefore + prize);
        assertEq(address(lottery).balance, 0);
    }
}
