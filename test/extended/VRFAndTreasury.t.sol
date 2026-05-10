// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseExtendedTest} from "./BaseExtended.t.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";

/**
 * @title Veritas VRF Fulfillment & Financial Settlement Test Suite
 * @author BitBoyz Team
 * @notice Validates the asynchronous oracle fulfillment logic and the mathematical integrity of pool distributions.
 * @dev Inherits from BaseExtendedTest. Focuses on the transition from 'Calculating' to 'Drawn',
 * the 2% protocol fee routing, and the security of the internal withdrawal vault.
 */
contract VRFAndTreasuryTest is BaseExtendedTest {
    /**
     * @notice Validates that the protocol correctly calculates the treasury fee and restarts the round.
     * @dev Confirms the 200 BPS (2%) protocol fee is routed to the treasury vault while the
     * remainder is allocated to the winner. Verifies that the state machine autonomously
     * initializes currentRoundId + 1 into the 'Open' phase[cite: 73, 127].
     */
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

    /**
     * @notice Ensures that the rawFulfillRandomWords entry point is strictly protected.
     * @dev Validates the OnlyCoordinatorCanFulfill guard, ensuring that only the authorized
     * vrfCoordinator address can trigger the draw logic[cite: 145].
     */
    function testRevertIfOnlyCoordinatorCanFulfill() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 123;
        vm.expectRevert(
            abi.encodeWithSelector(LotteryEX.OnlyCoordinatorCanFulfill.selector, address(this), address(vrfMock))
        );
        lottery.rawFulfillRandomWords(1, words);
    }

    /**
     * @notice Validates the 'Pull-over-Push' withdrawal pattern for prize distribution.
     * @dev Confirms that funds are successfully transferred from the pendingWithdrawals
     * vault to the winner's wallet and that the internal balance is zeroed post-transfer[cite: 152].
     */
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

    /**
     * @notice Verifies that an unexpected VRF callback safely aborts if the round is not in the 'Calculating' phase.
     * @dev Protects against out-of-order execution or stale oracle responses disrupting the active round.
     */
    function testFulfillRandomWordsWrongPhaseReturnsEarly() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 123;

        vm.prank(address(vrfMock));
        lottery.rawFulfillRandomWords(1, words);

        (,,, LotteryEX.Phase phase,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Open));
    }

    /**
     * @notice Ensures the withdrawPrize function reverts if the caller has no claimable balance.
     * @dev Acts as a secondary guard against empty or unauthorized withdrawal attempts.
     */
    function testRevertIfWithdrawPrizeNoFunds() public {
        vm.expectRevert(LotteryEX.NoFundsToWithdraw.selector);
        vm.prank(player1);
        lottery.withdrawPrize();
    }

    /**
     * @notice Validates the Tier 3 'Rollover Loop' logic for unsold ticket indices.
     * @dev Proves that if the VRF selects an unsold index, the contract autonomously iterates
     * through the bitmap to find the next valid ticket holder, ensuring a winner is always selected[cite: 83].
     */
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

    /**
     * @notice Verifies that the protocol handles failed ETH transfers gracefully during withdrawals.
     * @dev Utilizes the RejectETHEX mock contract to trigger a TransferFailed revert,
     * proving the robustness of the low-level .call implementation[cite: 150].
     */
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

/**
 * @title RejectETHEX Mock Contract
 * @author BitBoyz Team
 * @notice A specialized test contract designed to purchase tickets and then refuse the prize payout.
 * @dev Used to validate the 'TransferFailed' error branch within the LotteryEX withdrawal logic.
 */
contract RejectETHEX {
    /**
     * @notice The specific instance of the Autonomous Enterprise Engine this mock is designed to target.
     */
    LotteryEX public target;

    /**
     * @notice Initializes the mock with the address of the target lottery contract.
     * @param _target The address of the deployed LotteryEX instance.
     */
    constructor(LotteryEX _target) {
        target = _target;
    }

    /**
     * @notice Forwards msg.value to the autonomous engine to enter the lottery round.
     * @param index The specific ticket index to purchase within the bitmap.
     */
    function buy(uint8 index) external payable {
        uint8[] memory indices = new uint8[](1);
        indices[0] = index;
        target.batchBuyTickets{value: msg.value}(indices);
    }

    /**
     * @notice Attempts to withdraw prize funds; will trigger a revert in the target contract
     * because this mock lacks a receive() or fallback() function.
     */
    function claim() external {
        target.withdrawPrize();
    }
}
