// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

/**
 * @title Veritas Reveal & Draw Integrity Test Suite
 * @author BitBoyz Team
 * @notice Validates the cryptographic integrity of the commit-reveal scheme and the linear progression of the state machine.
 * @dev Inherits from BaseLotteryTest. This suite focuses on preventing out-of-order execution and ensuring secret-to-hash matching[cite: 231, 232].
 */
contract RevealAndDrawTest is BaseLotteryTest {
    /**
     * @notice Transitions the lottery environment to the 'SaleClosed' phase to prepare for reveal testing.
     * @dev Overrides the base setup to perform an initial purchase and administrative sale closure.
     */
    function setUp() public override {
        super.setUp();

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();
    }

    /**
     * @notice Ensures that a cryptographic hash cannot be committed unless the lottery is in the 'SaleClosed' phase.
     * @dev Validates the transition requirements that prevent the owner from committing a hash during active sales or after a previous commitment.
     */
    function testRevertIfCommitHashWrongPhase() public {
        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(owner);
        vm.expectRevert("Sale not closed");
        lottery.commitHash(committedHash);
    }

    /**
     * @notice Verifies that the reveal and draw logic cannot be triggered before a hash has been successfully committed.
     * @dev Enforces the strict sequential dependency of the Commit-Reveal fairness protocol.
     */
    function testRevertIfRevealWrongPhase() public {
        vm.prank(owner);
        vm.expectRevert("Hash not committed");
        lottery.revealAndDraw(SECRET);
    }

    /**
     * @notice Confirms that providing a secret that does not match the previously committed keccak256 hash results in a revert.
     * @dev Proves that the owner cannot change the secret value after participants have entered the pool.
     */
    function testRevertIfRevealWrongSecret() public {
        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(owner);
        vm.expectRevert("Secret does not match committed hash");
        // casting to bytes32 is safe because the string is under 32 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        lottery.revealAndDraw(bytes32("wrongSecret"));
    }

    /**
     * @notice Validates that the owner is prohibited from closing a sale if the participant pool is empty.
     * @dev This acts as a "Division-by-Zero" prevention check, ensuring the modulo calculation always has a non-zero divisor[cite: 233].
     */
    function testRevertIfCloseSaleNoParticipants() public {
        vm.prank(owner);
        Lottery emptyLottery = new Lottery(TICKET_PRICE, MAX_TICKETS);

        vm.prank(owner);
        vm.expectRevert("No participants");
        emptyLottery.closeSale();
    }

    /**
     * @notice Ensures that the closeSale function cannot be called if the lottery is already in a non-open phase.
     * @dev Prevents unauthorized re-entry into the sale-closing logic to maintain state machine integrity.
     */
    function testRevertIfCloseSaleWrongPhase() public {
        vm.prank(owner);
        vm.expectRevert("Lottery not open");
        lottery.closeSale();
    }
}
