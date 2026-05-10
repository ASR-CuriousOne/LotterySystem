// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

contract BatchTicketingTest is BaseExtendedTest {
    function testBatchBuyTickets() public {
        uint8[] memory indices = new uint8[](3);
        indices[0] = 1;
        indices[1] = 5;
        indices[2] = 10;

        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 3}(indices);

        (uint256 bitmap,, uint16 sold,, uint256 pool,) = lottery.rounds(1);
        assertEq(sold, 3);
        assertEq(pool, TICKET_PRICE * 3);
        assertTrue((bitmap & (uint256(1) << 1)) != 0);
        assertTrue((bitmap & (uint256(1) << 5)) != 0);
        assertTrue((bitmap & (uint256(1) << 10)) != 0);
    }

    function testRevertIfTicketAlreadySold() public {
        uint8[] memory indices1 = new uint8[](1);
        indices1[0] = 42;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices1);

        uint8[] memory indices2 = new uint8[](1);
        indices2[0] = 42;
        vm.prank(player2);
        vm.expectRevert(LotteryEX.TicketAlreadySold.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices2);
    }

    function testRevertIfIncorrectPayment() public {
        uint8[] memory indices = new uint8[](2);
        indices[0] = 1;
        indices[1] = 2;
        vm.prank(player1);
        vm.expectRevert(LotteryEX.IncorrectPayment.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);
    }

    function testRevertIfZeroTickets() public {
        uint8[] memory indices = new uint8[](0);
        vm.prank(player1);
        vm.expectRevert(LotteryEX.ZeroTickets.selector);
        lottery.batchBuyTickets{value: 0}(indices);
    }

    function testRevertIfExceedsMaxTickets() public {
        uint8[] memory indices = new uint8[](256);
        for (uint16 i = 0; i < 256; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            indices[i] = uint8(i);
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 256}(indices);

        uint8[] memory extra = new uint8[](1);
        extra[0] = 0;
        vm.prank(player2);
        vm.expectRevert(LotteryEX.ExceedsMaxTickets.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(extra);
    }

    function testVipDiscountApplied() public {
        uint8[] memory initial = new uint8[](5);
        for (uint8 i = 0; i < 5; i++) {
            initial[i] = i;
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 5}(initial);

        uint8[] memory discounted = new uint8[](2);
        discounted[0] = 5;
        discounted[1] = 6;

        uint256 discountPrice = (TICKET_PRICE * 90) / 100;

        vm.prank(player1);
        lottery.batchBuyTickets{value: discountPrice * 2}(discounted);

        (,, uint16 sold,,,) = lottery.rounds(1);
        assertEq(sold, 7);
    }

    function testRevertIfBatchBuyWrongPhase() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        uint8[] memory indices2 = new uint8[](1);
        indices2[0] = 2;
        vm.prank(player2);
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices2);
    }

    function testGetTicketPriceDirectly() public view {
        uint256 price = lottery.getTicketPrice(player1);
        assertEq(price, TICKET_PRICE);
    }
}
