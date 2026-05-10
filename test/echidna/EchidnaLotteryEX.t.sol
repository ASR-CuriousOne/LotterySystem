// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LotteryEX} from "../../src/LotteryEX.sol";
import {
    IVRFCoordinatorV2Plus
} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

contract EchidnaLotteryEX is LotteryEX {
    constructor() {
        ticketPrice = 0.01 ether;
        roundDuration = 1 days;
        drawTimeout = 1 days;
        vrfCoordinator = IVRFCoordinatorV2Plus(address(0x1));
        keyHash = bytes32(0);
        subscriptionId = 1;
        treasury = address(this);
        protocolFeeBps = 200;

        currentRoundId = 1;
        rounds[1].startTime = block.timestamp;
        rounds[1].phase = Phase.Open;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validRoundId() public view returns (bool) {
        return currentRoundId >= 1;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(rounds[currentRoundId].phase) <= 3;
    }

    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_ticketsSoldLimit() public view returns (bool) {
        return rounds[currentRoundId].ticketsSold <= 256;
    }
}
