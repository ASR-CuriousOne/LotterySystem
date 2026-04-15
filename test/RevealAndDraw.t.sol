// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Reveal and Draw Mechanics Tests
 * @notice Validates the commit-reveal cryptographic checks and state transitions.
 */
contract RevealAndDrawTest is BaseLotteryTest {
    /**
     * @notice Advances the lottery state to the Committed phase before each test.
     * @dev Overrides the BaseLotteryTest setUp function.
     */
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

    /**
     * @notice Ensures the transaction reverts if the revealed secret does not match the committed hash.
     * @dev Simulates the owner passing an incorrect secret payload.
     */
    function testRevertIfRevealWrongSecret() public {
        vm.expectRevert(Lottery.Lottery__HashMismatch.selector);
        vm.prank(owner);

        // casting to 'bytes32' is safe because the string "wrongSecret" is 11 bytes, well under the 32-byte limit
        // forge-lint: disable-next-line(unsafe-typecast)
        lottery.revealAndDraw(bytes32("wrongSecret"));
    }

    /**
     * @notice Ensures the draw function cannot be called twice.
     * @dev Attempts to call revealAndDraw while the phase is already in the Drawn state.
     */
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
