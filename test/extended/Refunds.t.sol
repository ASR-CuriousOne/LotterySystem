// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

contract RefundsTest is BaseExtendedTest {
    function testEnableRefundFallbackAndClaim() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 7;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        vm.expectRevert(LotteryEX.TimeoutNotReached.selector);
        lottery.enableRefundFallback();

        vm.warp(block.timestamp + DRAW_TIMEOUT + 1);
        lottery.enableRefundFallback();

        assertEq(lottery.currentRoundId(), 2);
        (,,, LotteryEX.Phase phase,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Refundable));

        vm.prank(player1);
        lottery.claimRefund(1, 7);

        assertEq(lottery.pendingWithdrawals(player1), TICKET_PRICE);

        vm.prank(player1);
        vm.expectRevert(LotteryEX.NotTicketOwner.selector);
        lottery.claimRefund(1, 7);
    }

    function testRevertIfClaimRefundWrongPhase() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 7;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.prank(player1);
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.claimRefund(1, 7);
    }

    function testRevertIfEnableRefundFallbackWrongPhase() public {
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.enableRefundFallback();
    }
}
