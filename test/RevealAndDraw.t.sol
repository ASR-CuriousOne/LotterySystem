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

    /**
     * @notice Validates the deterministic rollover math within the `revealAndDraw` execution.
     * @dev Forces the initial keccak256 modulo output to land on an unsold ticket index,
     * guaranteeing that the internal `while` loop executes to find the next valid bitmapped ticket.
     */
    function testRolloverLoopInReveal() public {
        // 1. Deploy a FRESH lottery instance as the 'owner' to bypass the suite's setUp() state
        vm.prank(owner);
        Lottery freshLottery = new Lottery(TICKET_PRICE);

        // 2. Player buys ONLY the final ticket (Index 255)
        vm.deal(player1, TICKET_PRICE);
        vm.prank(player1);
        freshLottery.buyTicket{value: TICKET_PRICE}(255);

        // 3. Close sale and commit hash on the fresh instance
        vm.prank(owner);
        freshLottery.closeSale();

        bytes32 localCommit = keccak256(abi.encodePacked(SECRET));
        vm.prank(owner);
        freshLottery.commitHash(localCommit);

        // 4. Roll to an arbitrary block to ensure the raw keccak256 modulo does NOT equal 255
        // This forces the while-loop to iterate until it hits the 255th bit
        vm.roll(100);

        // 5. Reveal and draw
        vm.prank(owner);
        freshLottery.revealAndDraw(SECRET);

        // Ensure the loop successfully rolled over and found the only buyer
        assertEq(freshLottery.winner(), player1);
    }

    /**
     * @notice Ensures the owner cannot commit a hash if the sale is not closed.
     * @dev Hits the final missing InvalidPhase branch inside commitHash.
     */
    function testRevertIfCommitHashWrongPhase() public {
        // The setUp() in this file leaves the contract in the Committed phase (2).
        // commitHash requires it to be in the SaleClosed phase (1).
        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.SaleClosed, Lottery.LotteryPhase.Committed
            )
        );
        vm.prank(owner);
        lottery.commitHash(bytes32("newHash"));
    }
}
