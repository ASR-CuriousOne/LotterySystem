// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

/**
 * @title Veritas Administrative Access Test Suite
 * @author BitBoyz Team
 * @notice Validates that privileged administrative functions are strictly restricted to the contract owner.
 * @dev Inherits from BaseLotteryTest. Utilizes vm.prank to simulate unauthorized access attempts
 * across the primary state-shifting functions.
 */
contract AdminTest is BaseLotteryTest {
    /**
     * @notice Verifies that non-owner addresses cannot trigger administrative lifecycle functions.
     * @dev Iterates through closeSale(), commitHash(), and revealAndDraw().
     * Confirms that the OnlyOwner modifier correctly triggers an EVM revert when called by an unauthorized player.
     * Also verifies that the legitimate owner can successfully execute these functions to progress the state.
     */
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
