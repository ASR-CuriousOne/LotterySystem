// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LotteryVRF} from "../src/LotteryVRF.sol";

contract EchidnaLotteryVRF is LotteryVRF {
    constructor() LotteryVRF(0.01 ether, address(0x1), bytes32(0), 1) {}

    /**
     * @notice Invariant: The contract balance must always cover the prize pool.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_balanceCoversPrizePool() public view returns (bool) {
        return address(this).balance >= prizePool;
    }

    /**
     * @notice Invariant: The VRF phase enum should never exceed 2.
     */
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(currentPhase) <= 2;
    }
}
