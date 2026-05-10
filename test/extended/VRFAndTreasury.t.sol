// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

contract VRFAndTreasuryTest is BaseExtendedTest {
    function testFulfillRandomWordsSplitsPoolAndRestarts() public {
        uint8[] memory p1Indices = new uint8[](1);
        p1Indices[0] = 5;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(p1Indices);

        uint8[] memory p2Indices = new uint8[](1);
        p2Indices[0] = 15;
        vm.prank(player2);
        lottery.batchBuyTickets{value: TICKET_PRICE}(p2Indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        vrfMock.fulfillRandomWords(1, 5);

        (, address winner,,, uint256 pool,) = lottery.rounds(1);
        assertEq(winner, player1);

        uint256 expectedTreasury = (pool * 200) / 10000;
        uint256 expectedWinner = pool - expectedTreasury;

        assertEq(lottery.pendingWithdrawals(treasury), expectedTreasury);
        assertEq(lottery.pendingWithdrawals(player1), expectedWinner);

        assertEq(lottery.currentRoundId(), 2);
        (,,, LotteryEX.Phase phase,,) = lottery.rounds(2);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Open));
    }

    function testRevertIfOnlyCoordinatorCanFulfill() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 123;
        vm.expectRevert(
            abi.encodeWithSelector(LotteryEX.OnlyCoordinatorCanFulfill.selector, address(this), address(vrfMock))
        );
        lottery.rawFulfillRandomWords(1, words);
    }

    function testWithdrawPrize() public {
        uint8[] memory p1Indices = new uint8[](1);
        p1Indices[0] = 5;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(p1Indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");
        vrfMock.fulfillRandomWords(1, 5);

        uint256 expectedWinner = lottery.pendingWithdrawals(player1);
        uint256 startingBalance = player1.balance;

        vm.prank(player1);
        lottery.withdrawPrize();

        assertEq(player1.balance, startingBalance + expectedWinner);
        assertEq(lottery.pendingWithdrawals(player1), 0);
    }

    function testFulfillRandomWordsWrongPhaseReturnsEarly() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 123;

        vm.prank(address(vrfMock));
        lottery.rawFulfillRandomWords(1, words);

        (,,, LotteryEX.Phase phase,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Open));
    }

    function testRevertIfWithdrawPrizeNoFunds() public {
        vm.expectRevert(LotteryEX.NoFundsToWithdraw.selector);
        vm.prank(player1);
        lottery.withdrawPrize();
    }

    function testFulfillRandomWordsRolloverLoop() public {
        uint8[] memory indices = new uint8[](1);
        indices[0] = 5;
        vm.prank(player1);
        lottery.batchBuyTickets{value: TICKET_PRICE}(indices);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        vrfMock.fulfillRandomWords(1, 4);

        (, address winner,,,,) = lottery.rounds(1);
        assertEq(winner, player1);
    }

    function testRevertIfWithdrawPrizeTransferFailed() public {
        RejectETHEX rejector = new RejectETHEX(lottery);
        vm.deal(address(rejector), 1 ether);
        rejector.buy{value: TICKET_PRICE}(5);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        vrfMock.fulfillRandomWords(1, 5);

        vm.expectRevert(LotteryEX.TransferFailed.selector);
        rejector.claim();
    }
}

contract RejectETHEX {
    LotteryEX public target;

    constructor(LotteryEX _target) {
        target = _target;
    }

    function buy(uint8 index) external payable {
        uint8[] memory indices = new uint8[](1);
        indices[0] = index;
        target.batchBuyTickets{value: msg.value}(indices);
    }

    function claim() external {
        target.withdrawPrize();
    }
}
