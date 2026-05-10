// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "../base/BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

contract RandomnessBiasTest is BaseLotteryTest {
    function test_MathematicalDistributionBias() public pure {
        uint256 participantsLength = 3;
        uint256 winsIndex0 = 0;
        uint256 winsIndex1 = 0;
        uint256 winsIndex2 = 0;

        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 secret = bytes32("static_secret");

        for (uint256 i = 0; i < 30000; i++) {
            uint256 winnerIndex = uint256(keccak256(abi.encodePacked(secret, i))) % participantsLength;

            if (winnerIndex == 0) winsIndex0++;
            else if (winnerIndex == 1) winsIndex1++;
            else if (winnerIndex == 2) winsIndex2++;
        }

        uint256 expectedWins = 10000;
        uint256 allowedVariance = 300;

        assertApproxEqAbs(winsIndex0, expectedWins, allowedVariance);
        assertApproxEqAbs(winsIndex1, expectedWins, allowedVariance);
        assertApproxEqAbs(winsIndex2, expectedWins, allowedVariance);
    }

    function test_LastMinuteSnipeDoesNotBreakMath() public {
        vm.roll(100);
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.roll(200);

        address sniper = makeAddr("sniper");
        hoax(sniper, TICKET_PRICE);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        (Lottery.LotteryPhase phase,, uint256 participantCount,,) = lottery.getLotteryInfo();

        assertEq(participantCount, 2);
        assertEq(uint256(phase), uint256(Lottery.LotteryPhase.SaleClosed));
    }
}
