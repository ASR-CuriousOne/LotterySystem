// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

/**
 * @title Veritas Chainlink Automation Test Suite
 * @author BitBoyz Team
 * @notice Validates the autonomous state transitions of the LotteryEX contract via Chainlink Keepers.
 * @dev Inherits from BaseExtendedTest. Specifically tests the conditional logic in checkUpkeep
 * and the state-shifting execution in performUpkeep.
 */
contract KeepersAutomationTest is BaseExtendedTest {
    /**
     * @notice Verifies that upkeep is not triggered if no tickets have been purchased, even after expiration.
     * @dev Ensures the protocol does not waste gas/LINK attempting to draw a lottery with zero participants.
     */
    function testCheckUpkeepReturnsFalseIfNoTickets() public {
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    /**
     * @notice Confirms that upkeep remains false if the round has neither expired nor reached capacity.
     * @dev Validates the "Open" state integrity during standard operation.
     */
    function testCheckUpkeepReturnsFalseIfNotExpired() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    /**
     * @notice Validates that selling all 256 tickets triggers an immediate upkeep requirement.
     * @dev Proves that the "soldOut" condition overrides the "timeExpired" condition for efficiency.
     */
    function testCheckUpkeepReturnsTrueWhenSoldOut() public {
        uint8[] memory indices = new uint8[](256);
        for (uint16 i = 0; i < 256; i++) {
            // casting to uint8 is safe because the loop is strictly bounded to 256 iterations
            // forge-lint: disable-next-line(unsafe-typecast)
            indices[i] = uint8(i);
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 256}(indices);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded);
    }

    /**
     * @notice Tests the successful transition from 'Open' to 'Calculating' upon upkeep execution.
     * @dev Uses vm.warp to simulate time progression and confirms the state machine progresses correctly.
     */
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

    /**
     * @notice Ensures performUpkeep reverts if the required conditions (time or capacity) are not met.
     * @dev Protects against unauthorized or premature draw attempts.
     */
    function testRevertIfPerformUpkeepConditionsNotMet() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    /**
     * @notice Confirms that checkUpkeep returns false if the round is already in the 'Calculating' phase.
     * @dev Prevents redundant oracle requests once a draw has already been initiated.
     */
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

    /**
     * @notice Verifies that performUpkeep reverts if called while the round is not in the 'Open' phase.
     * @dev Enforces strict linear phase progression within the autonomous engine.
     */
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

    /**
     * @notice Ensures the protocol rejects draw attempts for empty rounds.
     * @dev Validates the participant-count guard within the execution logic.
     */
    function testRevertIfPerformUpkeepNoTicketsSold() public {
        vm.warp(block.timestamp + ROUND_DURATION + 1);

        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    /**
     * @notice Validates that the protocol can be drawn immediately upon selling out, regardless of elapsed time.
     * @dev Confirms the autonomous engine's ability to handle high-velocity rounds.
     */
    function testPerformUpkeepSoldOutEarly() public {
        uint8[] memory indices = new uint8[](256);
        for (uint16 i = 0; i < 256; i++) {
            // casting to uint8 is safe because the loop is strictly bounded to 256 iterations
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
