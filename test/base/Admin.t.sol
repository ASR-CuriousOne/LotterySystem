// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

contract AdminTest is BaseLotteryTest {
    function testRevertIfNonOwnerCallsAdminFunctions() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(player1);
        vm.expectRevert();
        lottery.closeSale();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(player1);
        vm.expectRevert();
        lottery.commitHash(committedHash);

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(player1);
        vm.expectRevert();
        lottery.revealAndDraw(SECRET);
    }
}
