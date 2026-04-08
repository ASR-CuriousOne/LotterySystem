// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

contract AdminTest is BaseLotteryTest {
    function testRevertIfNonOwnerCallsAdminFunctions() public {
        vm.expectRevert();
        vm.prank(player1);
        lottery.closeSale();
    }
}
