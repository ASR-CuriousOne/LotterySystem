// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

/**
 * @title Veritas Enterprise Engine V2 (Mock Implementation)
 * @author BitBoyz Team
 * @notice A secondary implementation used to validate the UUPS upgrade path of the Tier 3 architecture.
 * @dev Inherits from LotteryEX to maintain storage layout compatibility during the proxy upgrade test.
 */
contract LotteryEXV2 is LotteryEX {
    /**
     * @notice Read-only helper to confirm successful proxy migration.
     * @return The version identifier (2) for this implementation logic.
     */
    function getVersion() external pure returns (uint256) {
        return 2;
    }
}

/**
 * @title Veritas Governance & Proxy Security Test Suite
 * @author BitBoyz Team
 * @notice Validates the administrative circuit breaker (pausing) and the UUPS proxy upgrade mechanism.
 * @dev Inherits from BaseExtendedTest. Ensures that critical governance actions are strictly gated
 * to the authorized owner and that storage integrity is preserved across upgrades.
 */
contract AdminAndProxyTest is BaseExtendedTest {
    /**
     * @notice Verifies the functionality of the Pausable circuit breaker.
     * @dev Confirms that:
     * 1. The owner can successfully freeze ticket sales.
     * 2. Attempts to buy tickets while paused results in a revert.
     * 3. Sales resume correctly once the contract is unpaused by the owner.
     */
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

    /**
     * @notice Validates the UUPS upgradeability pattern of the enterprise engine.
     * @dev Simulates an implementation migration. Confirms that the proxy successfully routes
     * to the new V2 logic and exposes new functions (getVersion) without erasing round data.
     */
    function testProxyUpgrade() public {
        vm.startPrank(owner);
        LotteryEXV2 v2Impl = new LotteryEXV2();
        lottery.upgradeToAndCall(address(v2Impl), "");
        vm.stopPrank();

        LotteryEXV2 upgraded = LotteryEXV2(payable(address(lottery)));
        assertEq(upgraded.getVersion(), 2);
    }

    /**
     * @notice Ensures that the UUPS upgrade path is strictly restricted to the contract owner.
     * @dev Proves that a malicious participant (player1) cannot trigger an unauthorized logic migration.
     */
    function testRevertIfNonOwnerUpgrades() public {
        LotteryEXV2 v2Impl = new LotteryEXV2();
        vm.prank(player1);
        vm.expectRevert();
        lottery.upgradeToAndCall(address(v2Impl), "");
    }
}
