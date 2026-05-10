// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

/**
 * @title Veritas Bitmapped Ticketing Test Suite
 * @author BitBoyz Team
 * @notice Validates the enterprise-grade batch purchasing logic and bitmapped storage integrity.
 * @dev Inherits from BaseExtendedTest. Specifically focuses on bitwise collision detection,
 * O(1) storage updates, and the programmatic VIP discount engine.
 */
contract BatchTicketingTest is BaseExtendedTest {
    /**
     * @notice Verifies that multiple tickets can be purchased in a single transaction using bitwise OR operations.
     * @dev Confirms that the uint256 bitmap correctly records indices and the prize pool accumulates aggregate payments.
     */
    function testBatchBuyTickets() public {
        uint8[] memory indices = new uint8[](3);
        indices[0] = 1;
        indices[1] = 5;
        indices[2] = 10;

        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 3}(indices);

        (uint256 bitmap,, uint16 sold,, uint256 pool,) = lottery.rounds(1);
        assertEq(sold, 3);
        assertEq(pool, TICKET_PRICE * 3);
        assertTrue((bitmap & (uint256(1) << 1)) != 0);
        assertTrue((bitmap & (uint256(1) << 5)) != 0);
        assertTrue((bitmap & (uint256(1) << 10)) != 0);
    }

    /**
     * @notice Validates the bitwise collision detection mechanism.
     * @dev Proves that attempting to purchase a bit (ticket index) that is already set to 1 results in a TicketAlreadySold revert.
     */
    function testRevertIfTicketAlreadySold() public {
        uint8[] memory indices1 = new uint8[](1);
        indices1[0] = 42;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices1);

        uint8[] memory indices2 = new uint8[](1);
        indices2[0] = 42;
        vm.prank(player2);
        vm.expectRevert(LotteryEX.TicketAlreadySold.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices2);
    }

    /**
     * @notice Ensures that the total ETH sent for a batch must exactly match the sum of the (potentially discounted) ticket prices.
     */
    function testRevertIfIncorrectPayment() public {
        uint8[] memory indices = new uint8[](2);
        indices[0] = 1;
        indices[1] = 2;
        vm.prank(player1);
        vm.expectRevert(LotteryEX.IncorrectPayment.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);
    }

    /**
     * @notice Confirms that the protocol rejects empty batch arrays to prevent gas-wasting zero-iteration loops.
     */
    function testRevertIfZeroTickets() public {
        uint8[] memory indices = new uint8[](0);
        vm.prank(player1);
        vm.expectRevert(LotteryEX.ZeroTickets.selector);
        lottery.batchBuyTickets{value: 0}(indices);
    }

    /**
     * @notice Validates the physical 256-bit boundary of the storage engine.
     * @dev Proves the contract reverts when total entries attempt to exceed the capacity of a single uint256 slot.
     */
    function testRevertIfExceedsMaxTickets() public {
        uint8[] memory indices = new uint8[](256);
        for (uint16 i = 0; i < 256; i++) {
            // casting to uint8 is safe because the loop is strictly bounded to 256 iterations
            // forge-lint: disable-next-line(unsafe-typecast)
            indices[i] = uint8(i);
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 256}(indices);

        uint8[] memory extra = new uint8[](1);
        extra[0] = 0;
        vm.prank(player2);
        vm.expectRevert(LotteryEX.ExceedsMaxTickets.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(extra);
    }

    /**
     * @notice Tests the programmatic VIP loyalty discount logic.
     * @dev Verifies that users with 5 or more previous participations successfully trigger the 10% price reduction.
     */
    function testVipDiscountApplied() public {
        uint8[] memory initial = new uint8[](5);
        for (uint8 i = 0; i < 5; i++) {
            initial[i] = i;
        }
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE * 5}(initial);

        uint8[] memory discounted = new uint8[](2);
        discounted[0] = 5;
        discounted[1] = 6;

        uint256 discountPrice = (TICKET_PRICE * 90) / 100;

        vm.prank(player1);
        lottery.batchBuyTickets{value: discountPrice * 2}(discounted);

        (,, uint16 sold,,,) = lottery.rounds(1);
        assertEq(sold, 7);
    }

    /**
     * @notice Confirms that batch ticket sales are strictly restricted to the 'Open' phase.
     * @dev Simulates a state transition to 'Calculating' via Chainlink Automation and verifies that subsequent purchase attempts revert.
     */
    function testRevertIfBatchBuyWrongPhase() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 1;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        uint8[] memory indices2 = new uint8[](1);
        indices2[0] = 2;
        vm.prank(player2);
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices2);
    }

    /**
     * @notice Validates the public-facing view function for ticket pricing.
     * @dev Ensures the UI can accurately fetch the current entry cost for a specific address.
     */
    function testGetTicketPriceDirectly() public view {
        uint256 price = lottery.getTicketPrice(player1);
        assertEq(price, TICKET_PRICE);
    }
}
