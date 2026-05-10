// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {LotteryVRF} from "../src/LotteryVRF.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

/**
 * @title Veritas VRF Lottery Test Suite
 * @author BitBoyz Team
 * @notice Validates the Chainlink VRF implementation (Tier 2) of the lottery protocol.
 * @dev Inherits from Foundry's Test. Orchestrates mock oracle interactions using the VRFCoordinatorV2Mock
 * to verify asynchronous randomness delivery and phase-gate integrity.
 */
contract LotteryVRFTest is Test {
    /**
     *  @notice The primary instance of the VRF-powered lottery being subjected to lifecycle testing.
     */
    LotteryVRF public lotteryVrf;

    /**
     *  @notice Local mock of the Chainlink VRF Coordinator used to simulate randomness fulfillment in a sandbox.
     */
    VRFCoordinatorV2Mock public vrfMock;

    /**
     * @notice Administrative address with privileged access to the draw and configuration functions.
     */
    address public owner = makeAddr("owner");

    /**
     * @notice Mock player address used for standard entry and winning verification.
     */
    address public player1 = makeAddr("player1");

    /**
     * @notice The mock subscription ID for simulated VRF billing and consumer management.
     */
    address public player2 = makeAddr("player2");

    /**
     *  @notice The mock Chainlink subscription ID used for simulated VRF billing and consumer management.
     */
    uint64 public subId;

    /**
     * @notice The standardized ticket cost (0.01 ETH) consistent across all project architectures.
     */
    uint256 public constant TICKET_PRICE = 0.01 ether;

    /**
     * @notice Configures the VRF test environment before each execution.
     * @dev Deploys the mock coordinator, manages subscription funding, and registers the lottery as a consumer.
     * Includes an explicit cast of "mock-key-hash" to bytes32, which is safe as the string length (13 bytes)
     * is well within the 32-byte slot capacity.
     * forge-lint: disable-next-line(unsafe-typecast)
     */
    function setUp() public {
        vrfMock = new VRFCoordinatorV2Mock(0.1 ether, 1e9);

        subId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subId, 100 ether);

        vm.prank(owner);
        // casting to 'bytes32' is safe because the string "mock-key-hash" is 13 bytes, well under the 32-byte limit
        // forge-lint: disable-next-line(unsafe-typecast)
        lotteryVrf = new LotteryVRF(TICKET_PRICE, address(vrfMock), bytes32("mock-key-hash"), subId);

        vrfMock.addConsumer(subId, address(lotteryVrf));

        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
    }

    /**
     * @notice Validates the full successful lifecycle of a VRF-powered draw.
     * @dev Simulates participant entry, owner draw requests, and mock fulfillment.
     * Asserts correct phase transitions (Open -> Calculating -> Drawn).
     */
    function testVRFDrawLifecycle() public {
        vm.prank(player1);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        vm.prank(player2);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        uint256 requestId = lotteryVrf.closeSaleAndDraw();

        assertEq(uint256(lotteryVrf.currentPhase()), 1); // Calculating

        vrfMock.fulfillRandomWords(requestId, address(lotteryVrf));

        assertEq(uint256(lotteryVrf.currentPhase()), 2); // Drawn
        address winner = lotteryVrf.winner();
        assertTrue(winner == player1 || winner == player2, "Winner not selected");

        console2.log("The VRF randomly selected:", winner);
    }

    /**
     * @notice Verifies that payments deviating from the strict ticket price result in an IncorrectPayment revert.
     */
    function test_RevertIf_BuyTicketWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert(LotteryVRF.IncorrectPayment.selector);
        lotteryVrf.buyTicket{value: 0.05 ether}(); // Paying too much
    }

    /**
     * @notice Confirms that ticket sales are blocked while the contract is awaiting the oracle result.
     */
    function test_RevertIf_BuyTicketWrongPhase() public {
        // Move to Calculating phase
        vm.prank(player1);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lotteryVrf.closeSaleAndDraw();

        // Attempt to buy while calculating
        vm.prank(player2);
        vm.expectRevert(LotteryVRF.InvalidPhase.selector);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();
    }

    /**
     * @notice Ensures administrative draw functions are strictly restricted to the authorized owner.
     */
    function test_RevertIf_CloseSaleNotOwner() public {
        vm.prank(player1); // Not the owner
        vm.expectRevert();
        lotteryVrf.closeSaleAndDraw();
    }

    /**
     * @notice Validates the division-by-zero prevention guard when the participant pool is empty.
     */
    function test_RevertIf_CloseSaleNoParticipants() public {
        vm.prank(owner);
        vm.expectRevert("No participants");
        lotteryVrf.closeSaleAndDraw();
    }

    /**
     * @notice Ensures prize claiming is gated behind the successful completion of an oracle draw.
     */
    function test_RevertIf_ClaimPrizeWrongPhase() public {
        vm.prank(player1);
        vm.expectRevert(LotteryVRF.InvalidPhase.selector);
        lotteryVrf.claimPrize(); // Phase is still Open
    }

    /**
     * @notice Verifies that only the mathematically selected winning address can withdraw the prize pool.
     * @dev Uses a single-participant draw to guarantee the winner identity for testing.
     */
    function test_RevertIf_ClaimPrizeNotWinner() public {
        vm.prank(player1);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        // Draw winner (Player 1 is the only participant, guaranteed to win)
        vm.prank(owner);
        uint256 reqId = lotteryVrf.closeSaleAndDraw();
        vrfMock.fulfillRandomWords(reqId, address(lotteryVrf));

        // Player 2 tries to claim Player 1's prize
        vm.prank(player2);
        vm.expectRevert(LotteryVRF.NotWinner.selector);
        lotteryVrf.claimPrize();
    }

    /**
     * @notice Validates error handling for failed ETH transfers to incompatible recipients.
     * @dev Utilizes the RejectETH contract to trigger the TransferFailed selector.
     */
    function test_RevertIf_TransferFailed() public {
        // Deploy a contract that rejects receiving ETH
        RejectETH rejector = new RejectETH(lotteryVrf);
        vm.deal(address(rejector), 1 ether);

        // Contract buys a ticket
        rejector.buy{value: TICKET_PRICE}();

        // Draw the winner (RejectETH contract wins)
        vm.prank(owner);
        uint256 reqId = lotteryVrf.closeSaleAndDraw();
        vrfMock.fulfillRandomWords(reqId, address(lotteryVrf));

        // Contract tries to claim, but its receive() function is missing, so it fails
        vm.expectRevert(LotteryVRF.TransferFailed.selector);
        rejector.claim();
    }

    /**
     * @notice Tests the protocol's resilience to out-of-order or stale oracle callbacks.
     * @dev Verifies that callbacks delivered in an incorrect phase return early without altering state.
     */
    function test_FulfillRandomWords_WrongPhase_ReturnsEarly() public {
        vm.prank(player1);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        uint256[] memory words = new uint256[](1);
        words[0] = 12345;

        // Prank the VRF Coordinator to force a raw callback while the phase is still 'Open'
        vm.prank(address(vrfMock));
        lotteryVrf.rawFulfillRandomWords(1, words);

        // Assert the phase didn't accidentally change to 'Drawn'
        assertEq(uint256(lotteryVrf.currentPhase()), 0); // Still Open
    }

    /**
     * @notice Prevents the owner from initiating multiple simultaneous randomness requests for a single round.
     */
    function test_RevertIf_CloseSaleWrongPhase() public {
        vm.prank(player1);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lotteryVrf.closeSaleAndDraw();

        // Try to trigger again while it's already calculating
        vm.prank(owner);
        vm.expectRevert(LotteryVRF.InvalidPhase.selector);
        lotteryVrf.closeSaleAndDraw();
    }
}

/**
 * @title RejectETH Mock (VRF Variant)
 * @author BitBoyz Team
 * @notice A specialized test contract used to simulate failed native ETH transfers.
 * @dev Deliberately lacks a receive() or fallback() function to force low-level .call operations to fail.
 */
contract RejectETH {
    /**
     * @notice The VRF lottery instance targeted for the transfer failure test.
     */
    LotteryVRF public target;

    /**
     * @notice Links the mock contract to the target VRF lottery instance.
     */
    constructor(LotteryVRF _target) {
        target = _target;
    }

    /**
     * @notice Forwards ETH from the test runner to enter the lottery pool.
     */
    function buy() external payable {
        target.buyTicket{value: msg.value}();
    }

    /**
     * @notice Attempts to withdraw the prize, triggering a TransferFailed revert in the target contract.
     */
    function claim() external {
        target.claimPrize();
    }

    // Deliberately omitting the receive() or fallback() function to reject incoming ETH
}
