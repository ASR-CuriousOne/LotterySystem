// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "../src/Lottery.sol";

/**
 * @notice Echidna testing contract.
 * Note: Echidna strictly requires the "echidna_" prefix, overriding standard camelCase conventions here.
 */
contract EchidnaLottery is Lottery {
    constructor() Lottery(0.01 ether) {}

    // Invariant 1: The contract's ETH balance should never be less than the recorded prize pool
    function echidna_balanceCoversPrizePool() public view returns (bool) {
        return address(this).balance >= prizePool;
    }

    // Invariant 2: The phase enum should never exceed the bounds of defined phases (0 to 3)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(currentPhase) <= 3;
    }
}
