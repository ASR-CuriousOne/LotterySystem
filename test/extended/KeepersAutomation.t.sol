// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

contract KeepersAutomationTest is BaseExtendedTest {
    function testCheckUpkeepReturnsFalseIfNoTickets() public {
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfNotExpired() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenSoldOut() public {
        uint8[] memory indices = new uint8[](256);
        for (uint16 i = 0; i < 256; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            indices[i] = uint8(i);
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 256}(indices);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepTransitionsState() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        (,,, LotteryEX.Phase phase,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Calculating));
    }

    function testRevertIfPerformUpkeepConditionsNotMet() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    function testCheckUpkeepReturnsFalseIfWrongPhase() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function testRevertIfPerformUpkeepWrongPhase() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    function testRevertIfPerformUpkeepNoTicketsSold() public {
        vm.warp(block.timestamp + ROUND_DURATION + 1);

        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    function testPerformUpkeepSoldOutEarly() public {
        uint8[] memory indices = new uint8[](256);
        for (uint16 i = 0; i < 256; i++) {
            // forge-lint: disable-next-line(unsafe-typecast)
            indices[i] = uint8(i);
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 256}(indices);

        lottery.performUpkeep("");

        (,,, LotteryEX.Phase phase,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Calculating));
    }
}
