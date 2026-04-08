// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

contract ClaimPrizeTest is BaseLotteryTest {
    function testRevertIfNonWinnerClaimsPrize() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();
        vm.prank(owner);
        lottery.closeSale();
        vm.prank(owner);
        lottery.commitHash(committedHash);
        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        address attacker = makeAddr("attacker");

        vm.expectRevert(abi.encodeWithSelector(Lottery.Lottery__NotWinner.selector, attacker));
        vm.prank(attacker);
        lottery.claimPrize();
    }
}
