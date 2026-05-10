// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LotteryVRF} from "../../src/LotteryVRF.sol";

/**
 * @title Veritas VRF Echidna Fuzzing Harness
 * @author BitBoyz Team
 * @notice A specialized property-based testing harness for the VRF-powered Lottery (Tier 2).
 * @dev Inherits from LotteryVRF. This contract allows the Echidna fuzzer to explore
 * the state space of the VRF implementation, ensuring that the asynchronous
 * nature of the oracle draw does not violate core financial invariants.
 */
contract EchidnaLotteryVRF is LotteryVRF {
    /**
     * @notice Initializes the VRF harness with dummy oracle parameters for isolated fuzzing.
     * @dev Hardcodes the ticket price to 0.01 ether. Uses dummy addresses and IDs for
     * the VRF components (Coordinator, KeyHash, SubID) as Echidna focuses on local
     * logic paths rather than external oracle network connectivity.
     */
    constructor() LotteryVRF(0.01 ether, address(0x1), bytes32(0), 1) {}

    /**
     * @notice Invariant: Prize pool solvency.
     * @dev Proves that the native ETH balance held by the contract is always sufficient
     * to pay out the internal prizePool accounting, even across asynchronous phases.
     * @return True if the contract is solvent.
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_balanceCoversPrizePool() public view returns (bool) {
        return address(this).balance >= prizePool;
    }

    /**
     * @notice Invariant: VRF state machine integrity.
     * @dev Ensures the currentPhase enum remains within the defined bounds (Open, Calculating, Drawn).
     * @return True if the phase index is 0, 1, or 2.
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(currentPhase) <= 2;
    }
}
