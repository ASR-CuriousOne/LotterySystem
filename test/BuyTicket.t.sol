// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Ticket Purchasing Constraints Tests
 * @notice Validates the logic and edge cases surrounding the buyTicket functionality.
 */
contract BuyTicketTest is BaseLotteryTest {
    /**
     * @notice Ensures tickets cannot be purchased after the sale phase has ended.
     * @dev Transitions the state to SaleClosed and expects a Lottery__InvalidPhase revert on subsequent buy attempts.
     */
    function testRevertIfBuyTicketAfterSaleClosed() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.Open, Lottery.LotteryPhase.SaleClosed
            )
        );
        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();
    }
}
