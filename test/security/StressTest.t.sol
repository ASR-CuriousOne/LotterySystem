// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "../base/BaseLottery.t.sol";

contract LotterySecurityTest is BaseLotteryTest {
    function test_MassiveConcurrentBuyers() public {
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

    function testFuzz_RevertIfOverpayment(uint256 amount) public {
        vm.assume(amount > TICKET_PRICE && amount < 100_000_000 ether);

        address whale = address(0x999);
        hoax(whale, amount);

        vm.expectRevert("Incorrect ticket price");
        lottery.buyTicket{value: amount}();
    }

    function test_SecurePrizeClaiming() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}();

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

    function invariant_ContractBalanceNeverBreaks() public view {
        (,, uint256 participantCount,,) = lottery.getLotteryInfo();
        uint256 expectedMinimumBalance = participantCount * TICKET_PRICE;

        if (lottery.prizePool() > 0) {
            assertGe(address(lottery).balance, expectedMinimumBalance);
        }
    }
}
