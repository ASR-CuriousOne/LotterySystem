// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Happy Path Lottery Lifecycle Test
 * @notice Verifies the flawless end-to-end execution of the lottery under normal conditions.
 */
contract HappyPathTest is BaseLotteryTest {
    /**
     * @notice Tests all five operational steps: Buy, Close, Commit, Reveal, and Claim.
     * @dev Simulates multiple players, fast-forwards block numbers, and asserts state changes and balances.
     */
    function testHappyPathFullLotteryLifecycle() public {
        // 1. Open Phase: Players buy tickets
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.prizePool(), TICKET_PRICE * 2);

        // 2. SaleClosed Phase: Owner closes the sale
        vm.prank(owner);
        lottery.closeSale();

        (Lottery.LotteryPhase phase,,,,) = lottery.getLotteryInfo();
        assertEq(uint256(phase), uint256(Lottery.LotteryPhase.SaleClosed));

        // 3. Committed Phase: Owner commits the hash
        vm.prank(owner);
        lottery.commitHash(committedHash);

        // 4. Drawn Phase: Owner reveals secret
        vm.roll(block.number + 10);

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        address winner = lottery.winner();
        assertTrue(winner == player1 || winner == player2, "Winner must be one of the players");

        // 5. Claim Prize
        uint256 winnerBalanceBefore = winner.balance;

        vm.prank(winner);
        lottery.claimPrize();

        assertEq(winner.balance, winnerBalanceBefore + (TICKET_PRICE * 2));
        assertEq(address(lottery).balance, 0);
    }
}
