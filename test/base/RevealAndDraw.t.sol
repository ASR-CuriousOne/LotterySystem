// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

contract RevealAndDrawTest is BaseLotteryTest {
    function setUp() public override {
        super.setUp();

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();
    }

    function testRevertIfCommitHashWrongPhase() public {
        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(owner);
        vm.expectRevert("Sale not closed");
        lottery.commitHash(committedHash);
    }

    function testRevertIfRevealWrongPhase() public {
        vm.prank(owner);
        vm.expectRevert("Hash not committed");
        lottery.revealAndDraw(SECRET);
    }

    function testRevertIfRevealWrongSecret() public {
        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(owner);
        vm.expectRevert("Secret does not match committed hash");
        // forge-lint: disable-next-line(unsafe-typecast)
        lottery.revealAndDraw(bytes32("wrongSecret"));
    }

    function testRevertIfCloseSaleNoParticipants() public {
        vm.prank(owner);
        Lottery emptyLottery = new Lottery(TICKET_PRICE, MAX_TICKETS);

        vm.prank(owner);
        vm.expectRevert("No participants");
        emptyLottery.closeSale();
    }

    function testRevertIfCloseSaleWrongPhase() public {
        vm.prank(owner);
        vm.expectRevert("Lottery not open");
        lottery.closeSale();
    }
}
