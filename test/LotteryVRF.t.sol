// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
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
        // 1. Deploy the Chainlink Mock Coordinator
        // BaseFee (0.1 LINK) and GasPriceLink (1e9)
        vrfMock = new VRFCoordinatorV2Mock(0.1 ether, 1e9);

        // 2. Create and fund a test subscription
        subId = vrfMock.createSubscription();
        vrfMock.fundSubscription(subId, 100 ether); // Fund with 100 mock LINK

        // 3. Deploy our VRF Lottery
        vm.prank(owner);
        lotteryVrf = new LotteryVRF(
            TICKET_PRICE,
            address(vrfMock),
            // casting to 'bytes32' is safe because the string "mock-key-hash" is 13 bytes, well under the 32-byte limit
            // forge-lint: disable-next-line(unsafe-typecast)
            bytes32("mock-key-hash"),
            subId
        );

        // 4. Add our Lottery as an authorized consumer of the subscription
        vrfMock.addConsumer(subId, address(lotteryVrf));

        // Fund players
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);
    }

    function testVRFDrawLifecycle() public {
        // Step 1: Players buy tickets
        vm.prank(player1);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        vm.prank(player2);
        lotteryVrf.buyTicket{value: TICKET_PRICE}();

        // Step 2: Owner requests a draw
        vm.prank(owner);
        // We can capture the returned requestId directly! No log parsing needed.
        uint256 requestId = lotteryVrf.closeSaleAndDraw();

        // Assert phase is now Calculating
        assertEq(uint256(lotteryVrf.currentPhase()), 1);

        // Step 3: Simulate the Chainlink Node fulfilling the request
        // The mock acts as the oracle here and calls fulfillRandomWords on our contract
        vrfMock.fulfillRandomWords(requestId, address(lotteryVrf));

        // Step 4: Verify the winner was selected
        assertEq(uint256(lotteryVrf.currentPhase()), 2); // Phase is now Drawn
        address winner = lotteryVrf.winner();
        assertTrue(winner == player1 || winner == player2, "Winner not selected");

        console2.log("The VRF randomly selected:", winner);
    }
}
