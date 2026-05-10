// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VRFV2PlusClient} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract MockVRF {
    uint256 public nextRequestId = 1;
    mapping(uint256 => address) public requestToConsumer;

    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns (uint256) {
        uint256 reqId = nextRequestId++;
        requestToConsumer[reqId] = msg.sender;
        return reqId;
    }

    function fulfillRandomWords(uint256 requestId, uint256 word) external {
        address consumer = requestToConsumer[requestId];
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        LotteryEX(payable(consumer)).rawFulfillRandomWords(requestId, words);
    }
}

contract BaseExtendedTest is Test {
    LotteryEX public lottery;
    MockVRF public vrfMock;

    address public owner = makeAddr("owner");
    address public player1 = makeAddr("player1");
    address public player2 = makeAddr("player2");
    address public treasury = makeAddr("treasury");

    uint256 public constant TICKET_PRICE = 0.01 ether;
    uint256 public constant ROUND_DURATION = 1 days;
    uint256 public constant DRAW_TIMEOUT = 1 days;
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant KEY_HASH = bytes32("mock");
    uint256 public constant SUB_ID = 1;

    function setUp() public virtual {
        vrfMock = new MockVRF();

        vm.startPrank(owner);
        LotteryEX implementation = new LotteryEX();

        bytes memory initData = abi.encodeCall(
            implementation.initialize,
            (address(vrfMock), TICKET_PRICE, ROUND_DURATION, DRAW_TIMEOUT, KEY_HASH, SUB_ID, treasury)
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        lottery = LotteryEX(payable(address(proxy)));
        vm.stopPrank();

        vm.deal(player1, 100 ether);
        vm.deal(player2, 100 ether);
    }
}
