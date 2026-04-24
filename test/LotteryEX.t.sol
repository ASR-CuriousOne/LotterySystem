// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LotteryEX} from "../src/LotteryEX.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

/**
 * @title LotteryEX Test Suite
 * @notice Validates the Multi-Round Engine, Keepers, Refunds, and Bitmap logic.
 */
contract LotteryEXTest is Test {
    /// @notice The lottery instance
    LotteryEX public lottery;

    /// @notice The local mock representation of the Chainlink VRF Coordinator
    VRFCoordinatorV2Mock public vrfMock;

    /// @notice Standardized test accounts
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public player3 = makeAddr("player3");

    /// @notice The mock Chainlink subscription ID
    uint64 public subId;

    /// @notice Standardized ticket price
    uint256 public constant TICKET_PRICE = 0.01 ether;

    /// @notice The standardized duration of a single lottery round
    uint256 public constant ROUND_DURATION = 1 days;

    /// @notice The standardized timeout period for the VRF oracle response
    uint256 public constant DRAW_TIMEOUT = 1 days;

    /// @notice Emitted when a new lottery round begins
    event RoundStarted(uint256 indexed roundId, uint256 startTime);

    /// @notice Emitted when a user successfully purchases a ticket
    event TicketPurchased(uint256 indexed roundId, address indexed buyer, uint8 ticketIndex);

    /// @notice Emitted when a round fails to draw and is opened for manual refunds
    event RefundFallbackEnabled(uint256 indexed roundId);

    /**
     * @notice Initializes the test environment before each run.
     * @dev Deploys the VRF mock, funds the subscription, and instantiates the multi-round engine.
     */
    function setUp() public {
        vrfMock = new VRFCoordinatorV2Mock(0.1 ether, 1e9);

        subId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subId, 100 ether);

        // casting to 'bytes32' is safe because the string "mock-key-hash" is 13 bytes, well under the 32-byte limit
        // forge-lint: disable-next-line(unsafe-typecast)
        bytes32 keyHash = bytes32("mock-key-hash");

        lottery = new LotteryEX(TICKET_PRICE, ROUND_DURATION, DRAW_TIMEOUT, address(vrfMock), keyHash, subId);
        vrfMock.addConsumer(subId, address(lottery));

        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);
        vm.deal(player3, 10 ether);
    }

    // ==========================================
    // BITMAP & PURCHASING TESTS
    // ==========================================

    /**
     * @notice Validates that purchasing a ticket correctly manipulates the bitwise registry.
     * @dev Asserts the bit corresponding to the ticket index flips to 1.
     */
    function test_BuyTicket_UpdatesBitmapAndPool() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(5); // Buy ticket index 5

        (,, uint256 prizePool,, uint256 bitmap, uint16 sold) = lottery.rounds(1);

        assertEq(prizePool, TICKET_PRICE);
        assertEq(sold, 1);
        assertEq(lottery.ticketOwners(1, 5), player1);

        // Check if the 5th bit is flipped to 1: (1 << 5) = 32
        assertTrue((bitmap & (uint256(1) << 5)) != 0, "Bitmap bit 5 should be 1");
    }

    /**
     * @notice Ensures users cannot overwrite or purchase an already claimed ticket index.
     */
    function test_RevertIf_BuyTicketAlreadySold() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(42);

        vm.prank(player2);
        vm.expectRevert(LotteryEX.TicketAlreadySold.selector);
        lottery.buyTicket{value: TICKET_PRICE}(42); // Try to buy the exact same ticket
    }

    /**
     * @notice Ensures the transaction reverts if the exact ticket price is not sent.
     */
    function test_RevertIf_BuyTicketWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert(LotteryEX.IncorrectPayment.selector);
        lottery.buyTicket{value: 0.05 ether}(10);
    }

    // ==========================================
    // CHAINLINK KEEPERS (UPKEEP) TESTS
    // ==========================================

    /**
     * @notice Validates that upkeep is ignored if the duration passes but no tickets were sold.
     * @dev Utilizes vm.warp to fast-forward the blockchain state.
     */
    function test_CheckUpkeep_ReturnsFalse_IfNoTicketsSold() public {
        // Fast forward past duration, but nobody bought tickets
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    /**
     * @notice Validates that upkeep is ignored before the round duration has expired.
     */
    function test_CheckUpkeep_ReturnsFalse_IfNotExpired() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);

        // Time has not passed yet
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    /**
     * @notice Validates that a valid upkeep correctly transitions the round to the Calculating state.
     */
    function test_PerformUpkeep_TransitionsState() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(10);

        // Fast forward time to trigger upkeep
        vm.warp(block.timestamp + ROUND_DURATION + 1);

        lottery.performUpkeep(""); // Anyone/Chainlink can call this

        (LotteryEX.Phase phase,,,,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Calculating));
    }

    /**
     * @notice Ensures manual triggers of the performUpkeep function revert if conditions are unmet.
     */
    function test_RevertIf_PerformUpkeep_ConditionsNotMet() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);

        // Time has NOT expired
        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    /**
     * @notice Ensures the oracle callback returns safely if called in the wrong phase.
     */
    function test_FulfillRandomWords_WrongPhase_ReturnsEarly() public {
        uint256[] memory words = new uint256[](1);
        words[0] = 12345;

        vm.prank(address(vrfMock));
        lottery.rawFulfillRandomWords(1, words);

        (LotteryEX.Phase phase,,,,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Open));
    }

    /**
     * @notice Evaluates the complex Keeper conditions when the lottery sells out early.
     */
    function test_CheckAndPerformUpkeep_SoldOutEarly() public {
        // Buy all 256 tickets
        for (uint16 i = 0; i < 256; i++) {
            address user = address(uint160(i + 100));
            hoax(user, TICKET_PRICE);

            // casting to 'uint8' is safe because the loop strictly bounds 'i' between 0 and 255
            // forge-lint: disable-next-line(unsafe-typecast)
            lottery.buyTicket{value: TICKET_PRICE}(uint8(i));
        }

        // Time has NOT expired, but tickets are sold out
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertTrue(upkeepNeeded, "Upkeep should be true when sold out");

        lottery.performUpkeep("");
        (LotteryEX.Phase phase,,,,,) = lottery.rounds(1);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Calculating));
    }

    /**
     * @notice Ensures performUpkeep cannot be called maliciously twice.
     */
    function test_RevertIf_PerformUpkeep_WrongPhase() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);
        vm.warp(block.timestamp + ROUND_DURATION + 1);

        lottery.performUpkeep(""); // Transitions to Calculating

        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep(""); // Try again
    }

    function test_RevertIf_BuyTicketWrongPhase() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep(""); // Changes phase to Calculating

        vm.prank(player2);
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.buyTicket{value: TICKET_PRICE}(2);
    }

    function test_CheckUpkeep_ReturnsFalse_IfWrongPhase() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep(""); // Now in Calculating

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    function test_RevertIf_PerformUpkeep_NoTicketsSold() public {
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        // Phase is Open, Time is expired, but 0 tickets sold
        vm.expectRevert(LotteryEX.ConditionsNotMet.selector);
        lottery.performUpkeep("");
    }

    function test_RevertIf_EnableRefundFallback_WrongPhase() public {
        // Phase is currently Open, not Calculating
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.enableRefundFallback();
    }

    function test_RevertIf_ClaimRefund_WrongPhase() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);
        // Phase is currently Open, not Refundable
        vm.expectRevert(LotteryEX.InvalidPhase.selector);
        lottery.claimRefund(1, 1);
    }

    function test_RevertIf_WithdrawPrize_TransferFailed() public {
        RejectETHEX rejector = new RejectETHEX(lottery);
        vm.deal(address(rejector), 1 ether);
        rejector.buy(1);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");
        vrfMock.fulfillRandomWords(1, address(lottery));

        vm.expectRevert(LotteryEX.TransferFailed.selector);
        rejector.claim();
    }

    // ==========================================
    // VRF CALLBACK & MULTI-ROUND ENGINE TESTS
    // ==========================================

    /**
     * @notice Tests the complete automated engine loop from drawing the winner to starting the next round.
     * @dev Simulates the VRF callback and verifies the instantiation of Round 2.
     */
    function test_FulfillRandomWords_SelectsWinnerAndRestarts() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(5);

        vm.prank(player2);
        lottery.buyTicket{value: TICKET_PRICE}(15);

        vm.warp(block.timestamp + ROUND_DURATION + 1);

        // Capture the VRF Request ID by listening to the mock (or reading state in a real scenario)
        // Since it's the first request on the mock, ID is 1
        lottery.performUpkeep("");

        // Fulfill VRF
        vrfMock.fulfillRandomWords(1, address(lottery));

        // 1. Check Round 1 Winner & Vault
        (,,, address winner,,) = lottery.rounds(1);
        assertTrue(winner == player1 || winner == player2, "Winner must be p1 or p2");
        assertEq(lottery.pendingWithdrawals(winner), TICKET_PRICE * 2);

        // 2. Check Auto-Restart (Round 2 should be Open)
        assertEq(lottery.currentRoundId(), 2);
        (LotteryEX.Phase phase,, uint256 prizePool,,,) = lottery.rounds(2);
        assertEq(uint256(phase), uint256(LotteryEX.Phase.Open));
        assertEq(prizePool, 0); // Fresh pool
    }

    // ==========================================
    // PULL-OVER-PUSH VAULT TESTS
    // ==========================================

    /**
     * @notice Ensures a declared winner can successfully pull funds from their pending withdrawals vault.
     */
    function test_WithdrawPrize_Success() public {
        // Setup winner
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(1);
        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");
        vrfMock.fulfillRandomWords(1, address(lottery));

        // Withdraw
        uint256 startingBalance = player1.balance;

        vm.prank(player1);
        lottery.withdrawPrize();

        assertEq(player1.balance, startingBalance + TICKET_PRICE);
        assertEq(lottery.pendingWithdrawals(player1), 0); // CEI check
    }

    /**
     * @notice Prevents unauthorized or empty withdrawals from the central prize vault.
     */
    function test_RevertIf_WithdrawPrize_NoFunds() public {
        vm.prank(player2); // Did not win
        vm.expectRevert(LotteryEX.NoFundsToWithdraw.selector);
        lottery.withdrawPrize();
    }

    // ==========================================
    // LIVENESS GUARD & REFUND TESTS
    // ==========================================

    /**
     * @notice Simulates an oracle outage and validates the manual refund recovery mechanism.
     * @dev Triggers upkeep, ignores the VRF response, fast-forwards the timeout, and processes refunds.
     */
    function test_EnableRefundFallback_And_ClaimRefund() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}(7);

        vm.warp(block.timestamp + ROUND_DURATION + 1);
        lottery.performUpkeep("");

        // Oracle crashes here! No VRF fulfillment happens.

        // Player 1 tries to refund too early
        vm.expectRevert(LotteryEX.TimeoutNotReached.selector);
        lottery.enableRefundFallback();

        // Fast forward past the DRAW_TIMEOUT
        vm.warp(block.timestamp + DRAW_TIMEOUT + 1);

        // Enable fallback
        vm.expectEmit(true, false, false, false);
        emit RefundFallbackEnabled(1);
        lottery.enableRefundFallback();

        // Ensure Round 2 started automatically to save the protocol
        assertEq(lottery.currentRoundId(), 2);

        // Claim Refund for Round 1, Ticket 7
        vm.prank(player1);
        lottery.claimRefund(1, 7);

        // Check the vault
        assertEq(lottery.pendingWithdrawals(player1), TICKET_PRICE);

        // Ensure they can't double-claim
        vm.prank(player1);
        vm.expectRevert(LotteryEX.NotTicketOwner.selector);
        lottery.claimRefund(1, 7);
    }
}

/**
 * @title RejectETHEX Dummy Contract
 * @notice A malicious contract designed to fail ETH transfers for the EX architecture.
 */
contract RejectETHEX {
    LotteryEX public target;

    constructor(LotteryEX _target) {
        target = _target;
    }

    function buy(uint8 index) external payable {
        target.buyTicket{value: 0.01 ether}(index);
    }

    function claim() external {
        target.withdrawPrize();
    }
}
