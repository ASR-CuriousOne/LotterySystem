// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LotteryEX} from "../../src/LotteryEX.sol";
import {
    IVRFCoordinatorV2Plus
} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";

/**
 * @title Veritas Enterprise Engine Echidna Harness
 * @author BitBoyz Team
 * @notice A specialized testing harness for the Tier 3 Autonomous Enterprise Engine (LotteryEX).
 * @dev Inherits from LotteryEX. This harness allows the Echidna fuzzer to validate the
 * high-efficiency bitmapped storage and the autonomous state transitions of the enterprise-grade engine.
 */
contract EchidnaLotteryEX is LotteryEX {
    /**
     * @notice Initializes the Tier 3 harness with production-spec parameters for local fuzzing.
     * @dev Manually sets storage variables (bypassing the initializer) to establish a
     * consistent state for the Echidna engine. Configures a 200 BPS (2%) protocol fee
     * and initializes the primary round.
     */
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

    /**
     * @notice Invariant: Round ID integrity.
     * @dev Ensures that the autonomous round counter never resets or underflows during state transitions.
     * @return True if the currentRoundId is always 1 or greater.
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validRoundId() public view returns (bool) {
        return currentRoundId >= 1;
    }

    /**
     * @notice Invariant: Enterprise phase bounds.
     * @dev Validates that the autonomous state machine never enters an undefined phase.
     * @return True if the phase index remains between 0 (Open) and 3 (Refundable).
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_validPhaseBounds() public view returns (bool) {
        return uint256(rounds[currentRoundId].phase) <= 3;
    }

    /**
     * @notice Invariant: Bitmapped capacity limit.
     * @dev Proves that the bitmapped storage engine strictly adheres to the 256-ticket physical limit.
     * @return True if the ticketsSold counter never exceeds the 256-bit storage slot capacity.
     */
    // The 'echidna_' prefix is a mandatory naming convention for the Echidna fuzzer
    // forge-lint: disable-next-line(mixed-case-function)
    function echidna_ticketsSoldLimit() public view returns (bool) {
        return rounds[currentRoundId].ticketsSold <= 256;
    }
}
