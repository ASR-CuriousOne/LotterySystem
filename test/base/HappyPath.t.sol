// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

contract HappyPathTest is BaseLotteryTest {
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
