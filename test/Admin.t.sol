// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

/**
 * @title Administrative Access Control Tests
 * @notice Verifies that administrative functions are protected by the onlyOwner modifier.
 */
contract AdminTest is BaseLotteryTest {
    /**
     * @notice Ensures that non-owners cannot call the closeSale function.
     * @dev Uses vm.prank to simulate a call from an unauthorized player and expects a generic revert.
     */
    function testRevertIfNonOwnerCallsAdminFunctions() public {
        vm.expectRevert();
        vm.prank(player1);
        lottery.closeSale();
    }
}
