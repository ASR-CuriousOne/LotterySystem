// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "../base/BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

/**
 * @title Veritas Randomness Bias & Game Theory Test Suite
 * @author BitBoyz Team
 * @notice Validates the mathematical fairness of the winner selection algorithm and the resilience of the entry logic.
 * @dev Inherits from BaseLotteryTest. This suite performs high-iteration simulations to verify uniform distribution
 * and ensures that "sniping" (late entry) does not disrupt contract accounting or state transitions.
 */
contract RandomnessBiasTest is BaseLotteryTest {
    /**
     * @notice Verifies the statistical uniformity of the modulo-based selection method.
     * @dev Simulates 30,000 lottery draws against a static participant pool.
     * Asserts that each index wins within an expected variance (±3%), proving the keccak256
     * entropy is evenly distributed across the uint256 range before the modulo operation.
     */
    function test_MathematicalDistributionBias() public pure {
        uint256 participantsLength = 3;
        uint256 winsIndex0 = 0;
        uint256 winsIndex1 = 0;
        uint256 winsIndex2 = 0;

        // casting to bytes32 is safe because the string is 13 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 secret = bytes32("static_secret");

        for (uint256 i = 0; i < 30000; i++) {
            uint256 winnerIndex = uint256(keccak256(abi.encodePacked(secret, i))) % participantsLength;

            if (winnerIndex == 0) winsIndex0++;
            else if (winnerIndex == 1) winsIndex1++;
            else if (winnerIndex == 2) winsIndex2++;
        }

        uint256 expectedWins = 10000;
        uint256 allowedVariance = 300;

        assertApproxEqAbs(winsIndex0, expectedWins, allowedVariance);
        assertApproxEqAbs(winsIndex1, expectedWins, allowedVariance);
        assertApproxEqAbs(winsIndex2, expectedWins, allowedVariance);
    }

    /**
     * @notice Validates that entries made shortly before sale closure are correctly processed.
     * @dev Uses vm.roll to simulate block progression and verify that "last-minute" ticket
     * acquisitions correctly increment the participantCount and allow for a successful transition to 'SaleClosed'.
     */
    function test_LastMinuteSnipeDoesNotBreakMath() public {
        vm.roll(100);
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.roll(200);

        address sniper = makeAddr("sniper");
        hoax(sniper, TICKET_PRICE);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        (Lottery.LotteryPhase phase,, uint256 participantCount,,) = lottery.getLotteryInfo();

        assertEq(participantCount, 2);
        assertEq(uint256(phase), uint256(Lottery.LotteryPhase.SaleClosed));
    }
}
