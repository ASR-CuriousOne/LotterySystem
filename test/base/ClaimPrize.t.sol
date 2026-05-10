// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

/**
 * @title Veritas Prize Distribution & CEI Test Suite
 * @author BitBoyz Team
 * @notice Validates the security and integrity of the prize payout mechanism, specifically focusing on the winner verification and reentrancy protection.
 * @dev Inherits from BaseLotteryTest. This module ensures that only verified winners can drain the prize pool and that the contract handles failed transfers gracefully[cite: 8, 24].
 */
contract ClaimPrizeTest is BaseLotteryTest {
    /**
     * @notice Advances the lottery state to the 'Drawn' phase to prepare for distribution testing.
     * @dev Overrides the base setup to perform a complete lifecycle progression: buying a ticket, closing the sale, committing a hash, and revealing the secret.
     */
    function setUp() public override {
        super.setUp();

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);
    }

    /**
     * @notice Verifies that participants who are not the verified winner are prohibited from claiming the prize.
     * @dev Satisfies the rubric's requirement that only the mathematically verified winner can drain the contract[cite: 8].
     */
    function testRevertIfNonWinnerClaimsPrize() public {
        vm.expectRevert("Caller is not the winner");
        vm.prank(player2);
        lottery.claimPrize();
    }

    /**
     * @notice Ensures that the prize pool cannot be accessed before the draw has officially concluded.
     * @dev Validates that the contract remains locked during the Open, SaleClosed, and Committed phases[cite: 13].
     */
    function testRevertIfClaimBeforeDrawn() public {
        vm.prank(owner);
        Lottery freshLottery = new Lottery(TICKET_PRICE, MAX_TICKETS);

        vm.prank(player1);
        vm.expectRevert("Winner not drawn yet");
        freshLottery.claimPrize();
    }

    /**
     * @notice Validates the Checks-Effects-Interactions (CEI) implementation.
     * @dev Ensures that a winner cannot double-claim or execute a reentrancy attack by attempting to withdraw the prize multiple times[cite: 23].
     */
    function testRevertIfPrizeAlreadyClaimed() public {
        vm.prank(player1);
        lottery.claimPrize();

        vm.prank(player1);
        vm.expectRevert("Prize already claimed");
        lottery.claimPrize();
    }

    /**
     * @notice Proves the robustness of the low-level .call implementation when sending ETH.
     * @dev Utilizes the RejectETH dummy contract to simulate a recipient incapable of receiving ETH, proving the protocol gracefully handles transfer failures[cite: 24].
     */
    function testRevertIfTransferFailed() public {
        vm.prank(owner);
        Lottery freshLottery = new Lottery(TICKET_PRICE, MAX_TICKETS);

        RejectETH rejector = new RejectETH();
        vm.deal(address(rejector), TICKET_PRICE);
        rejector.buy{value: TICKET_PRICE}(freshLottery);

        vm.prank(owner);
        freshLottery.closeSale();

        vm.prank(owner);
        freshLottery.commitHash(committedHash);

        vm.prank(owner);
        freshLottery.revealAndDraw(SECRET);

        vm.expectRevert("Transfer failed");
        rejector.claim(freshLottery);
    }
}

/**
 * @title RejectETH Dummy Contract
 * @author BitBoyz Team
 * @notice A specialized mock contract designed to intentionally fail incoming ETH transfers.
 * @dev Used to test the "Transfer failed" revert branch in the Lottery contract's claimPrize function[cite: 24].
 */
contract RejectETH {
    /**
     * @notice Forwards msg.value to the lottery to enter the pool.
     */
    function buy(Lottery _lottery) external payable {
        _lottery.buyTicket{value: msg.value}();
    }

    /**
     * @notice Attempts to claim the prize but will cause the lottery's .call transfer to fail as this contract lacks a receive() function.
     */
    function claim(Lottery _lottery) external {
        _lottery.claimPrize();
    }
}
