// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "../src/Lottery.sol";

/**
 * @title Echidna Fuzzing Target
 * @notice Provides invariant tests for the Echidna property-based fuzzer.
 * @dev Inherits from the Lottery contract to expose its internal state for invariant checking.
 */
contract EchidnaLottery is Lottery {
    /**
     * @notice Initializes the target contract with a standard ticket price.
     */
    constructor() Lottery(0.01 ether) {}

    /**
     * @notice Invariant 1: The contract's ETH balance should never be less than the recorded prize pool.
     * @dev Ensures strict accounting so funds can never be drained maliciously.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_balanceCoversPrizePool() public view returns (bool) {
        return address(this).balance >= prizePool;
    }

    /**
     * @notice Invariant 2: The phase enum should never exceed the bounds of defined phases (0 to 3).
     * @dev Validates state transition boundaries to catch unexpected memory/storage corruption.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(currentPhase) <= 3;
    }
}
