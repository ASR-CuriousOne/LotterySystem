// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lottery} from "../../src/Lottery.sol";

contract EchidnaLottery is Lottery {
    constructor() Lottery(0.01 ether, 100) {}

    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_balanceCoversPrizePool() public view returns (bool) {
        return address(this).balance >= prizePool;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(currentPhase) <= 3;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_participantsUnderLimit() public view returns (bool) {
        return participants.length <= maxTickets;
    }
}
