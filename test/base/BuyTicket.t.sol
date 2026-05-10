// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";

/**
 * @title Veritas Ticketing & Capacity Test Suite
 * @author BitBoyz Team
 * @notice Validates the core ticketing logic, including price enforcement, phase gating, and participant capacity.
 * @dev Inherits from BaseLotteryTest. This suite ensures that the contract adheres to strict financial and
 * state-machine rules during the entry phase[cite: 14, 15].
 */
contract BuyTicketTest is BaseLotteryTest {
    /**
     * @notice Ensures that entries with incorrect payment amounts are rejected by the contract.
     * @dev Validates that users cannot underpay to "steal odds" or overpay, which would break the prize pool formula[cite: 18, 20].
     */
    function testRevertIfBuyTicketWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert("Incorrect ticket price");
        lottery.buyTicket{value: TICKET_PRICE - 1}();
    }

    /**
     * @notice Verifies that ticket purchases are strictly prohibited after the sale has been closed.
     * @dev Proves the contract successfully locks the participant array once the owner initiates the draw sequence[cite: 11].
     */
    function testRevertIfBuyTicketAfterSaleClosed() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(player2);
        vm.expectRevert("Lottery not open");
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    /**
     * @notice Validates that the contract strictly enforces the maximum ticket capacity.
     * @dev Proves that the MAX_TICKETS variable halts single-ticket purchases once the established cap is hit[cite: 31].
     */
    function testRevertIfSoldOut() public {
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * MAX_TICKETS}(MAX_TICKETS);

        vm.prank(player2);
        vm.expectRevert("Ticket limit reached");
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    /**
     * @notice Tests the end-to-end functionality of purchasing multiple tickets in a single transaction.
     * @dev Validates the custom presentation requirement by proving the dynamic array inflates correctly during batching[cite: 4].
     */
    function testBatchBuyTickets() public {
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 5}(5);

        (,, uint256 participants, uint256 pool,) = lottery.getLotteryInfo();
        assertEq(participants, 5);
        assertEq(pool, TICKET_PRICE * 5);
    }

    /**
     * @notice Ensures that the total ETH sent for a batch purchase exactly matches the aggregate ticket price.
     * @dev Prevents accounting drift during multi-ticket entries[cite: 18, 20].
     */
    function testRevertIfBatchBuyWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert("Incorrect total price");
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(5);
    }

    /**
     * @notice Confirms that the batched ticketing function cannot be used to bypass phase-based entry locks.
     * @dev Plugs a potential vulnerability where a user might attempt to enter after the SaleClosed transition via the batch function[cite: 26].
     */
    function testRevertIfBatchBuyWrongPhase() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(player2);
        vm.expectRevert("Lottery not open");
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(2);
    }

    /**
     * @notice Protects the contract against "whale" attackers attempting to exceed capacity via loops.
     * @dev Ensures that a single batch purchase cannot breach the MAX_TICKETS hard cap[cite: 32].
     */
    function testRevertIfBatchBuyExceedsLimit() public {
        vm.prank(player1);
        vm.expectRevert("Exceeds ticket limit");
        lottery.batchBuyTickets{value: TICKET_PRICE * (MAX_TICKETS + 1)}(MAX_TICKETS + 1);
    }

    /**
     * @notice Validates that batch purchases must include at least one ticket.
     * @dev Acts as an EVM optimization check to prevent users from wasting gas on empty, zero-iteration loops[cite: 33].
     */
    function testRevertIfBatchBuyZeroTickets() public {
        vm.prank(player1);
        vm.expectRevert("Must buy at least one ticket");
        lottery.batchBuyTickets{value: 0}(0);
    }

    /**
     * @notice Verifies the accuracy of the ticket counting view function.
     * @dev Ensures that the state correctly tracks and returns the number of entries owned by a specific address across multiple purchases.
     */
    function testGetTicketCount() public {
        assertEq(lottery.getTicketCount(player1), 0);

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(player1), 1);

        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();

        assertEq(lottery.getTicketCount(player1), 1);

        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 2}(2);

        assertEq(lottery.getTicketCount(player1), 3);
        assertEq(lottery.getTicketCount(player2), 1);
    }
}
