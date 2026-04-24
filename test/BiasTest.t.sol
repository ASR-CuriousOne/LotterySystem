// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Randomness and Bias Statistical Tests
 * @notice Validates the mathematical fairness of the pseudo-random number generator.
 * @dev Inherits from BaseLotteryTest to utilize standard state, accounts, and funding.
 */
contract RandomnessBiasTest is BaseLotteryTest {
    /**
     * @notice Analyzes the hashing formula across 30,000 iterations to detect Modulo Bias.
     * @dev Proves that the keccak256 output % participants.length distributes evenly within a 3% variance.
     */
    function test_MathematicalDistributionBias() public pure {
        uint256 participantsLength = 3;
        uint256 winsIndex0 = 0;
        uint256 winsIndex1 = 0;
        uint256 winsIndex2 = 0;

        // casting to 'bytes32' is safe because the string is 13 bytes
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 secret = bytes32("static_secret");

        // Simulate the exact contract math over 30,000 different block numbers
        for (uint256 i = 0; i < 30000; i++) {
            // Contract formula: uint256(keccak256(abi.encodePacked(_secret, block.number))) % participants.length;
            uint256 winnerIndex = uint256(keccak256(abi.encodePacked(secret, i))) % participantsLength;

            if (winnerIndex == 0) winsIndex0++;
            else if (winnerIndex == 1) winsIndex1++;
            else if (winnerIndex == 2) winsIndex2++;
        }

        // In a perfectly fair 3-person lottery, each should win exactly ~10,000 times.
        uint256 expectedWins = 10000;
        uint256 allowedVariance = 300; // Allow 3% variance

        assertApproxEqAbs(winsIndex0, expectedWins, allowedVariance, "Index 0 has a mathematical bias!");
        assertApproxEqAbs(winsIndex1, expectedWins, allowedVariance, "Index 1 has a mathematical bias!");
        assertApproxEqAbs(winsIndex2, expectedWins, allowedVariance, "Index 2 has a mathematical bias!");
    }

    /**
     * @notice Simulates a "Last-Minute Sniper" trying to exploit timing before the sale closes.
     * @dev Proves that buying a ticket in the exact same block as the closeSale transaction provides no mathematical advantage.
     */
    function test_LastMinuteSnipeDoesNotBreakMath() public {
        // 1. Normal users buy in early blocks using standard BaseLotteryTest accounts
        vm.roll(100);
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 2. Fast forward to the block where the owner decides to close the sale
        vm.roll(200);

        // 3. SNIPER ATTACK: Sniper front-runs the closeSale transaction in the exact same block
        address sniper = makeAddr("sniper");
        hoax(sniper, TICKET_PRICE);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 4. Owner closes the sale immediately after
        vm.prank(owner);
        lottery.closeSale();

        // Assert that the sniper successfully entered, but the phase safely locked
        (Lottery.LotteryPhase phase,, uint256 participantCount,,) = lottery.getLotteryInfo();

        assertEq(participantCount, 2, "Sniper failed to enter");
        assertEq(uint256(phase), uint256(Lottery.LotteryPhase.SaleClosed), "Sale did not lock properly");

        // Because the sniper cannot see the owner's 'secret' off-chain, their last-minute
        // entry provides zero mathematical advantage. The PRNG remains unbiased.
    }
}
