// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

contract LotteryEXV2 is LotteryEX {
    function getVersion() external pure returns (uint256) {
        return 2;
    }
}

contract AdminAndProxyTest is BaseExtendedTest {
    function testPauseAndUnpause() public {
        vm.prank(owner);
        lottery.pause();

        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;

        vm.prank(player1);
        vm.expectRevert();
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.prank(owner);
        lottery.unpause();

        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);
        (,, uint16 sold,,,) = lottery.rounds(1);
        assertEq(sold, 1);
    }

    function testProxyUpgrade() public {
        vm.startPrank(owner);
        LotteryEXV2 v2Impl = new LotteryEXV2();
        lottery.upgradeToAndCall(address(v2Impl), "");
        vm.stopPrank();

        LotteryEXV2 upgraded = LotteryEXV2(payable(address(lottery)));
        assertEq(upgraded.getVersion(), 2);
    }

    function testRevertIfNonOwnerUpgrades() public {
        LotteryEXV2 v2Impl = new LotteryEXV2();
        vm.prank(player1);
        vm.expectRevert();
        lottery.upgradeToAndCall(address(v2Impl), "");
    }
}
