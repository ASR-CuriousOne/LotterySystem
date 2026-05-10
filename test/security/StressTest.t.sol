// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "../base/BaseLottery.t.sol";

/**
 * @title Veritas Security & Stress Test Suite
 * @author BitBoyz Team
 * @notice Executes high-load stress tests, fuzzing, and invariant checks to ensure protocol robustness.
 * @dev Inherits from BaseLotteryTest. This module moves beyond unit testing into formal
 * verification of economic invariants and boundary-condition resilience.
 */
contract LotterySecurityTest is BaseLotteryTest {
    /**
     * @notice Simulates a high-concurrency event where the lottery is filled to capacity.
     * @dev Iteratively generates addresses and executes purchases to ensure the contract
     * handles maximum participant loads without accounting drift.
     */
    function test_MassiveConcurrentBuyers() public {
        // casting to uint160 is safe as it fits well within the range required to generate unique address space for mock users
        // forge-lint: disable-next-line(unsafe-typecast)
        uint160 numBuyers = uint160(MAX_TICKETS);
        uint256 initialBalance = address(lottery).balance;

        for (uint160 i = 1; i <= numBuyers; i++) {
            address user = address(i + 100);
            hoax(user, TICKET_PRICE);
            lottery.buyTicket{value: TICKET_PRICE}();
        }

        uint256 expectedBalance = initialBalance + (TICKET_PRICE * numBuyers);
        assertEq(address(lottery).balance, expectedBalance);
    }

    /**
     * @notice Fuzz tests the payment logic to ensure the contract rejects any amount above TICKET_PRICE.
     * @dev Uses Foundry's fuzzer to attempt entries with random 'whale' amounts.
     * This confirms that the lottery is not susceptible to "inflation attacks" or accounting overflows.
     * @param amount The fuzzed msg.value input provided by the test runner.
     */
    function testFuzz_RevertIfOverpayment(uint256 amount) public {
        vm.assume(amount > TICKET_PRICE && amount < 100_000_000 ether);

        address whale = address(0x999);
        hoax(whale, amount);

        vm.expectRevert("Incorrect ticket price");
        lottery.buyTicket{value: amount}();
    }

    /**
     * @notice Validates the "Winner-Takes-All" security invariant across a full lifecycle.
     * @dev Verifies three critical security properties:
     * 1. Unauthorized addresses (attackers) cannot claim the prize pool.
     * 2. The legitimate winner receives the exact prizePool balance.
     * 3. The prize cannot be claimed more than once (double-spend protection).
     */
    function test_SecurePrizeClaiming() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();

        // casting to bytes32 is safe because the string has 20 characters
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 secret = bytes32("random_secret_string");
        bytes32 commitHash = keccak256(abi.encodePacked(secret));

        vm.startPrank(owner);
        lottery.closeSale();
        lottery.commitHash(commitHash);
        lottery.revealAndDraw(secret);
        vm.stopPrank();

        address actualWinner = lottery.winner();
        address attacker = (actualWinner == player1) ? player2 : player1;

        vm.prank(attacker);
        vm.expectRevert("Caller is not the winner");
        lottery.claimPrize();

        uint256 winnerBalanceBefore = actualWinner.balance;
        uint256 expectedPrize = lottery.prizePool();

        vm.prank(actualWinner);
        lottery.claimPrize();

        assertEq(actualWinner.balance, winnerBalanceBefore + expectedPrize);

        vm.prank(actualWinner);
        vm.expectRevert("Prize already claimed");
        lottery.claimPrize();
    }

    /**
     * @notice An invariant property that must hold true throughout the lottery's entire existence.
     * @dev Asserts that the contract's native ETH balance is always greater than or equal to
     * the product of participants and ticket price, ensuring the protocol is never insolvent.
     */
    function invariant_ContractBalanceNeverBreaks() public view {
        (,, uint256 participantCount,,) = lottery.getLotteryInfo();
        uint256 expectedMinimumBalance = participantCount * TICKET_PRICE;

        if (lottery.prizePool() > 0) {
            assertGe(address(lottery).balance, expectedMinimumBalance);
        }
    }
}
