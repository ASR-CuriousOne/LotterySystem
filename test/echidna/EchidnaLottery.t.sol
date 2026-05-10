// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "../../src/Lottery.sol";

/**
 * @title Veritas Echidna Fuzzing Harness
 * @author BitBoyz Team
 * @notice A specialized testing contract designed for the Echidna security fuzzer.
 * @dev Inherits from the base Lottery contract to expose internal state for property-based testing.
 * This harness defines high-level invariants that must hold true across thousands of randomly generated
 * transaction sequences to prove the protocol's mathematical and financial integrity.
 */
contract EchidnaLottery is Lottery {
    /**
     * @notice Initializes the fuzzer with standardized economic parameters.
     * @dev Hardcodes the ticket price to 0.01 ether and the capacity to 100 entries
     * to create a consistent search space for the Echidna fuzzer.
     */
    constructor() Lottery(0.01 ether, 100) {}

    /**
     * @notice Invariant: Solvency check.
     * @dev Ensures that the contract's actual ETH balance is always sufficient to cover the
     * internal prizePool accounting. If this returns false, the protocol is insolvent.
     * @return True if the native balance is greater than or equal to the recorded prize pool.
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_balanceCoversPrizePool() public view returns (bool) {
        return address(this).balance >= prizePool;
    }

    /**
     * @notice Invariant: State machine integrity.
     * @dev Validates that the currentPhase enum never drifts into an undefined state.
     * @return True if the phase index is within the defined bounds (0 to 3).
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(currentPhase) <= 3;
    }

    /**
     * @notice Invariant: Capacity constraint.
     * @dev Proves that the participant array can never physically exceed the maxTickets limit,
     * protecting the contract against unintended storage inflation.
     * @return True if the participants list length is within the established cap.
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_participantsUnderLimit() public view returns (bool) {
        return participants.length <= maxTickets;
    }
}
