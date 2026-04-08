// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

contract BuyTicketTest is BaseLotteryTest {
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
