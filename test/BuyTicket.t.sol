// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Ticket Purchasing Constraints Tests
 * @notice Validates the logic and edge cases surrounding the buyTicket functionality.
 */
contract BuyTicketTest is BaseLotteryTest {
    /**
     * @notice Ensures tickets cannot be purchased after the sale phase has ended.
     * @dev Transitions the state to SaleClosed and expects a Lottery__InvalidPhase revert on subsequent buy attempts.
     */
    function testRevertIfBuyTicketAfterSaleClosed() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.Open, Lottery.LotteryPhase.SaleClosed
            )
        );
        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    /**
     * @notice Ensures purchasing a specific ticket index correctly updates the bitmapped storage.
     * @dev Validates the O(1) storage compression by using bitwise operations to check if the specific bit was flipped.
     */
    function testBuySpecificTicketUpdatesBitmap() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(42); // Buy ticket 42

        // Check if the 42nd bit is flipped to 1
        uint256 bitmap = lottery.ticketBitmap();
        assertTrue((bitmap & (uint256(1) << 42)) != 0, "Bitmap bit 42 should be 1");
        assertEq(lottery.ticketOwners(42), player1);
    }

    /**
     * @notice Ensures that attempting to purchase the same specific ticket index twice reverts.
     * @dev Hits the `Lottery__TicketAlreadySold` custom error branch by verifying the bitwise state mask.
     */
    function testRevertIfTicketAlreadySold() public {
        vm.deal(player1, TICKET_PRICE * 2);

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(42); // Purchase index 42

        // Attempt to breach the bitmask
        vm.prank(player1);
        vm.expectRevert(Lottery.Lottery__TicketAlreadySold.selector);
        lottery.buyTicket{value: TICKET_PRICE}(42);
    }

    /**
     * @notice Ensures that the contract strictly bounds ticket sales to 256.
     * @dev Hits the `Lottery__SoldOut` custom error branch by exhaustively purchasing all 256 available tickets.
     */
    function testRevertIfSoldOut() public {
        // Purchase the absolute maximum limit of 256 tickets
        for (uint160 i = 0; i < 256; i++) {
            address buyer = address(uint160(1000 + i));
            vm.deal(buyer, TICKET_PRICE);
            vm.prank(buyer);
            lottery.buyTicket{value: TICKET_PRICE}();
        }

        // The 257th attempt must revert, protecting the uint256 storage bounds
        vm.deal(address(999), TICKET_PRICE);
        vm.prank(address(999));
        vm.expectRevert(Lottery.Lottery__SoldOut.selector);
        lottery.buyTicket{value: TICKET_PRICE}();
    }

    /**
     * @notice Ensures purchasing a specific ticket index requires the exact ticket price.
     * @dev Hits the `Lottery__IncorrectTicketPrice` custom error branch in the overloaded `buyTicket(uint8)`.
     */
    function testRevertIfBuySpecificTicketWrongPrice() public {
        vm.deal(player1, TICKET_PRICE * 2);

        // Test Underpayment
        vm.prank(player1);
        vm.expectRevert(
            abi.encodeWithSelector(Lottery.Lottery__IncorrectTicketPrice.selector, TICKET_PRICE, TICKET_PRICE - 1)
        );
        lottery.buyTicket{value: TICKET_PRICE - 1}(42);

        // Test Overpayment
        vm.prank(player1);
        vm.expectRevert(
            abi.encodeWithSelector(Lottery.Lottery__IncorrectTicketPrice.selector, TICKET_PRICE, TICKET_PRICE + 1)
        );
        lottery.buyTicket{value: TICKET_PRICE + 1}(42);
    }

    /**
     * @notice Ensures purchasing a specific ticket index fails if the phase is wrong.
     * @dev Hits the InvalidPhase branch in the overloaded buyTicket(uint8).
     */
    function testRevertIfBuySpecificTicketWrongPhase() public {
        // 1. Buy a dummy ticket so closeSale() doesn't revert with NoParticipants
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 2. Owner successfully closes the sale
        vm.prank(owner);
        lottery.closeSale();

        // 3. Attempt to buy a specific ticket while the phase is SaleClosed
        vm.prank(player1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Lottery.Lottery__InvalidPhase.selector, Lottery.LotteryPhase.Open, Lottery.LotteryPhase.SaleClosed
            )
        );
        lottery.buyTicket{value: TICKET_PRICE}(42);
    }
}
