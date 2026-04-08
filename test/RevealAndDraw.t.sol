// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

contract RevealAndDrawTest is BaseLotteryTest {
    function setUp() public override {
        super.setUp();

        // Advance state to Committed for these specific tests
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);
    }

    function testRevertIfRevealWrongSecret() public {
        vm.expectRevert(Lottery.Lottery__HashMismatch.selector);
        vm.prank(owner);
        lottery.revealAndDraw(bytes32("wrongSecret"));
    }

    function testRevertIfSecondRevealAndDraw() public {
        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.Committed, Lottery.LotteryPhase.Drawn
            )
        );
        vm.prank(owner);
        lottery.revealAndDraw(SECRET);
    }
}
