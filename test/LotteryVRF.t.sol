// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {LotteryVRF} from "../src/LotteryVRF.sol";
import {VRFCoordinatorV2Mock} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";

contract LotteryVRFTest is Test {
    LotteryVRF public lotteryVrf;
    VRFCoordinatorV2Mock public vrfMock;

    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");

    uint64 public subId;
    uint256 public constant TICKET_PRICE = 0.01 ether;

    function setUp() public {
        vrfMock = new VRFCoordinatorV2Mock(0.1 ether, 1e9);

        subId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subId, 100 ether);

        vm.prank(owner);
        lotteryVrf = new LotteryVRF(TICKET_PRICE, address(vrfMock), bytes32("mock-key-hash"), subId);

        vrfMock.addConsumer(subId, address(lotteryVrf));

        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
    }

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

    function test_RevertIf_BuyTicketWrongPrice() public {
        vm.prank(player1);
        vm.expectRevert(LotteryVRF.IncorrectPayment.selector);
        lotteryVrf.buyTicket{value: 0.05 ether}(); // Paying too much
    }

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

    function test_RevertIf_CloseSaleNotOwner() public {
        vm.prank(player1); // Not the owner
        vm.expectRevert();
        lotteryVrf.closeSaleAndDraw();
    }

    function test_RevertIf_CloseSaleNoParticipants() public {
        vm.prank(owner);
        vm.expectRevert("No participants");
        lotteryVrf.closeSaleAndDraw();
    }

    function test_RevertIf_ClaimPrizeWrongPhase() public {
        vm.prank(player1);
        vm.expectRevert(LotteryVRF.InvalidPhase.selector);
        lotteryVrf.claimPrize(); // Phase is still Open
    }

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
}

/**
 * @notice A dummy contract that buys a ticket but has no receive() function,
 * forcing the ETH transfer to fail when claimPrize() is called.
 */
contract RejectETH {
    LotteryVRF public target;

    constructor(LotteryVRF _target) {
        target = _target;
    }

    function buy() external payable {
        target.buyTicket{value: msg.value}();
    }

    function claim() external {
        target.claimPrize();
    }

    // Deliberately omitting the receive() or fallback() function to reject incoming ETH
}
