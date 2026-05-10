// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

contract BuyTicketTest is BaseLotteryTest {
    function testRevertIfBuyTicketWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert("Incorrect ticket price");
        lottery.buyTicket{value: TICKET_PRICE - 1}();
    }

    function testRevertIfBuyTicketAfterSaleClosed() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(player2);
        vm.expectRevert("Lottery not open");
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testRevertIfSoldOut() public {
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * MAX_TICKETS}(MAX_TICKETS);

        vm.prank(player2);
        vm.expectRevert("Ticket limit reached");
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    function testBatchBuyTickets() public {
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 5}(5);

        (,, uint256 participants, uint256 pool,) = lottery.getLotteryInfo();
        assertEq(participants, 5);
        assertEq(pool, TICKET_PRICE * 5);
    }

    function testRevertIfBatchBuyWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert("Incorrect total price");
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(5);
    }

    function testRevertIfBatchBuyWrongPhase() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(player2);
        vm.expectRevert("Lottery not open");
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(2);
    }

    function testRevertIfBatchBuyExceedsLimit() public {
        vm.prank(player1);
        vm.expectRevert("Exceeds ticket limit");
        lottery.batchBuyTickets{value: TICKET_PRICE * (MAX_TICKETS + 1)}(MAX_TICKETS + 1);
    }

    function testRevertIfBatchBuyZeroTickets() public {
        vm.prank(player1);
        vm.expectRevert("Must buy at least one ticket");
        lottery.batchBuyTickets{value: 0}(0);
    }

    function testGetTicketCount() public {
        assertEq(lottery.getTicketCount(player1), 0);

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(player1), 1);

        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(player1), 1);

        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(2);

        assertEq(lottery.getTicketCount(player1), 3);
        assertEq(lottery.getTicketCount(player2), 1);
    }
}
