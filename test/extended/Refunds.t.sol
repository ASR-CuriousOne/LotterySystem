// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

/**
 * @title Veritas Trustless Refund Test Suite
 * @author BitBoyz Team
 * @notice Validates the fallback mechanisms designed to protect user capital during extended oracle or keeper outages.
 * @dev Inherits from BaseExtendedTest. Focuses on the DRAW_TIMEOUT boundary conditions and the integrity of the
 * Refundable state machine transition.
 */
contract RefundsTest is BaseExtendedTest {
    /**
     * @notice Validates the end-to-end "Happy Path" for the trustless refund mechanism.
     * @dev This test confirms that:
     * 1. Refunds cannot be triggered before the specific DRAW_TIMEOUT has elapsed[cite: 92, 250].
     * 2. Successful expiration transitions the round to the 'Refundable' phase and increments the currentRoundId[cite: 92].
     * 3. Legitimate ticket owners can claim their original 0.01 ETH entry fee into their pending withdrawal vault[cite: 90].
     * 4. Double-claiming a refund for the same ticket index is strictly prohibited[cite: 142].
     */
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

    /**
     * @notice Ensures that users cannot claim refunds while a round is still in the 'Open' or 'Calculating' phases.
     * @dev Protects the protocol's prize pool integrity by enforcing phase gating for all capital exits[cite: 66, 156].
     */
    function testRevertIfClaimRefundWrongPhase() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 7;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.prank(player1);
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.claimRefund(1, 7);
    }

    /**
     * @notice Verifies that the refund fallback cannot be initialized unless the round is stuck in the 'Calculating' state.
     * @dev Prevents the trustless timeout from being used to prematurely abort active ticket sales in the 'Open' phase[cite: 156].
     */
    function testRevertIfEnableRefundFallbackWrongPhase() public {
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.enableRefundFallback();
    }
}
