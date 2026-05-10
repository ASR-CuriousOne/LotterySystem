// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LotteryEX} from "../../src/LotteryEX.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {VRFV2PlusClient} from "chainlink-brownie-contracts/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Veritas Mock VRF Coordinator
 * @author BitBoyz Team
 * @notice Simulates the Chainlink VRF v2.5 Coordinator for local testing of the Tier 3 engine.
 * @dev Manages simulated request IDs and routes asynchronous callbacks to the LotteryEX consumer.
 * This is a critical component for validating autonomous fulfillment without an active oracle network.
 */
contract MockVRF {
    /**
     * @notice Incremental counter used to generate unique identifiers for simulated oracle requests.
     */
    uint256 public nextRequestId = 1;
    /**
     * @notice Maps a generated requestId to the address of the consuming contract for callback routing.
     */
    mapping(uint256 => address) public requestToConsumer;

    /**
     * @notice Mocks the requestRandomWords entry point used by the Tier 3 Autonomous Engine.
     * @dev Records the msg.sender as the consumer and returns a new request ID.
     * @return reqId The unique identifier for the simulated request.
     */
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest calldata) external returns (uint256) {
        uint256 reqId = nextRequestId++;
        requestToConsumer[reqId] = msg.sender;
        return reqId;
    }

    /**
     * @notice Manually triggers the oracle callback to simulate randomness fulfillment.
     * @dev Calls the consumer's rawFulfillRandomWords function with the provided simulated entropy.
     * @param requestId The ID of the request to satisfy.
     * @param word The simulated random value (entropy) to be delivered to the consumer.
     */
    function fulfillRandomWords(uint256 requestId, uint256 word) external {
        address consumer = requestToConsumer[requestId];
        uint256[] memory words = new uint256[](1);
        words[0] = word;
        LotteryEX(payable(consumer)).rawFulfillRandomWords(requestId, words);
    }
}

/**
 * @title Veritas Tier 3 Foundational Test Infrastructure
 * @author BitBoyz Team
 * @notice Establishes the testing environment for the LotteryEX Enterprise Engine behind a UUPS Proxy.
 * @dev Inherits from Foundry's Test. Provisions the MockVRF, handles ERC1967 proxy initialization,
 * and standardizes network parameters (timeouts, prices) for all child test modules.
 */
contract BaseExtendedTest is Test {
    /**
     * @notice The LotteryEX instance accessed through an ERC1967 Proxy.
     */
    LotteryEX public lottery;

    /**
     * @notice The local instance of the simulated VRF Coordinator.
     */
    MockVRF public vrfMock;

    /**
     *  @notice Administrative address for the Tier 3 engine, managing upgrades and pausing.
     */
    address public owner = makeAddr("owner");

    /**
     * @notice Standardized player identity for entry and withdrawal testing.
     */
    address public player1 = makeAddr("player1");

    /**
     * @notice Secondary player identity for concurrency and bitmapped storage verification.
     */
    address public player2 = makeAddr("player2");

    /**
     * @notice Address designated to receive protocol fees from the autonomous engine.
     */
    address public treasury = makeAddr("treasury");

    /**
     *  @notice Standardized entry price (0.01 ETH) for Tier 3 testing.
     */
    uint256 public constant TICKET_PRICE = 0.01 ether;

    /**
     * @notice The duration (1 day) after which Chainlink Automation can trigger a draw.
     */
    uint256 public constant ROUND_DURATION = 1 days;

    /**
     * @notice The grace period (1 day) after expiration before users can trigger a trustless refund.
     */
    uint256 public constant DRAW_TIMEOUT = 1 days;

    // casting to bytes32 is safe because it occupies only 4 bytes of the 32-byte slot
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant KEY_HASH = bytes32("mock");

    /**
     * @notice Mock subscription identifier used for simulated VRF billing.
     */
    uint256 public constant SUB_ID = 1;

    /**
     * @notice Initializes the Tier 3 testing environment before each execution.
     * @dev Orchestrates the following:
     * 1. Deploys the MockVRF and the LotteryEX implementation.
     * 2. Encodes the initialization calldata for the UUPS Proxy.
     * 3. Deploys the ERC1967Proxy and links it to the implementation.
     * 4. Provisions mock identities with 100 ETH for stress testing.
     */
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
