// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LotteryEX} from "../src/LotteryEX.sol";

/**
 * @title Echidna Fuzzing Target for LotteryEX
 * @notice Provides invariant tests for the advanced multi-round lottery.
 */
contract EchidnaLotteryEX is LotteryEX {
    // We pass dummy addresses and parameters for the VRF/Keepers to isolate the core logic
    constructor()
        LotteryEX(
            0.01 ether, // Ticket Price
            1 days, // Round Duration
            1 days, // Draw Timeout
            address(0x1), // VRF Coordinator Mock
            bytes32(0), // Key Hash
            1 // Sub ID
        )
    {}

    /**
     * @notice Invariant: The active round ID must never drop below 1.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validRoundId() public view returns (bool) {
        return currentRoundId >= 1;
    }

    /**
     * @notice Invariant: The phase enum for the current round should never exceed 3.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        // Access the mapping directly and read the .phase property
        LotteryEX.Phase phase = rounds[currentRoundId].phase;
        return uint256(phase) <= 3;
    }

    /**
     * @notice Invariant: The number of tickets sold in a round can never physically exceed 256.
     * This protects the bitmap and arithmetic bounds.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_ticketsSoldLimit() public view returns (bool) {
        // Access the mapping directly and read the .ticketsSold property
        uint16 sold = rounds[currentRoundId].ticketsSold;
        return sold <= 256;
    }
}
