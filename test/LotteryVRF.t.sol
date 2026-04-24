// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {LotteryVRF} from "../src/LotteryVRF.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

/**
 * @title VRF Lottery Test Suite
 * @notice Validates the Chainlink VRF implementation of the lottery, including mock oracle interactions.
 */
contract LotteryVRFTest is Test {
    /// @notice The primary VRF lottery instance being tested
    LotteryVRF public lotteryVrf;

    /// @notice The local mock representation of the Chainlink VRF Coordinator
    VRFCoordinatorV2Mock public vrfMock;

    /// @notice Standardized test accounts
    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");

    /// @notice The mock Chainlink subscription ID
    uint64 public subId;

    /// @notice Standardized ticket price for the test suite
    uint256 public constant TICKET_PRICE = 0.01 ether;

    /**
     * @notice Initializes the test environment before each run.
     * @dev Deploys the VRF mock, creates and funds a subscription, and deploys the lottery contract.
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
     * @notice Tests the complete lifecycle of the VRF lottery.
     * @dev Simulates ticket purchases, the draw request, and the asynchronous oracle callback.
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
     * @notice Ensures transactions revert if the exact ticket price is not sent.
     */
    function test_RevertIf_BuyTicketWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert(LotteryVRF.IncorrectPayment.selector);
        lotteryVrf.buyTicket{value: 0.05 ether}(); // Paying too much
    }

    /**
     * @notice Ensures users cannot purchase tickets while the oracle is calculating the winner.
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
     * @notice Validates that access control correctly prevents non-owners from drawing the lottery.
     */
    function test_RevertIf_CloseSaleNotOwner() public {
        vm.prank(player1); // Not the owner
        vm.expectRevert();
        lotteryVrf.closeSaleAndDraw();
    }

    /**
     * @notice Ensures the lottery cannot be drawn if no one has purchased a ticket.
     */
    function test_RevertIf_CloseSaleNoParticipants() public {
        vm.prank(owner);
        vm.expectRevert("No participants");
        lotteryVrf.closeSaleAndDraw();
    }

    /**
     * @notice Ensures the prize cannot be claimed before the oracle has delivered the result.
     */
    function test_RevertIf_ClaimPrizeWrongPhase() public {
        vm.prank(player1);
        vm.expectRevert(LotteryVRF.InvalidPhase.selector);
        lotteryVrf.claimPrize(); // Phase is still Open
    }

    /**
     * @notice Ensures that only the selected winner can execute the claim function.
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
     * @notice Validates the TransferFailed error by forcing a failed ETH push to a smart contract.
     * @dev Utilizes the RejectETH dummy contract to intentionally fail the receive operation.
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
     * @notice Ensures the oracle callback safely returns without altering state if called in the wrong phase.
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
     * @notice Ensures the owner cannot trigger the draw twice.
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
 * @title RejectETH Dummy Contract
 * @notice A malicious or incompatible contract designed to fail ETH transfers.
 * @dev Used strictly for testing the error handling of the claimPrize function.
 */
contract RejectETH {
    LotteryVRF public target;

    /**
     * @notice Initializes the dummy contract with the target lottery address.
     */
    constructor(LotteryVRF _target) {
        target = _target;
    }

    /**
     * @notice Forwards the msg.value to the lottery contract to purchase a ticket.
     */
    function buy() external payable {
        target.buyTicket{value: msg.value}();
    }

    /**
     * @notice Attempts to claim the prize from the target lottery.
     */
    function claim() external {
        target.claimPrize();
    }

    // Deliberately omitting the receive() or fallback() function to reject incoming ETH
}
