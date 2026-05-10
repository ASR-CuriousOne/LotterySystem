// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../../src/Lottery.sol";

/**
 * @title Veritas Base Lottery Test Infrastructure
 * @author BitBoyz Team
 * @notice Provides the foundational environment and state for the Lottery unit test modules.
 * @dev Deploys the target contract, provisions mock identities, and pre-calculates
 * cryptographic commitments to ensure consistency across inherited test suites.
 */
contract BaseLotteryTest is Test {
    /**
     * @notice The primary instance of the Lottery contract being subjected to unit testing.
     */
    Lottery public lottery;

    /**
     *  @notice The administrative address designated as the contract owner in the setup.
     */
    address public owner;

    /**
     *  @notice A mock player address used to simulate legitimate entries and unauthorized access attempts.
     */
    address public player1;

    /**
     *  @notice A secondary mock player address used for multi-participant and concurrency testing.
     */
    address public player2;

    /**
     *  @notice Standardized ticket price used for all test cases (0.01 ether).
     */
    uint256 public constant TICKET_PRICE = 0.01 ether;

    /**
     *  @notice Standardized entry limit used for capacity and overflow testing (100).
     */
    uint256 public constant MAX_TICKETS = 100;

    // casting to bytes32 is safe because string is only 17 bytes
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant SECRET = bytes32("superSecretValue");

    /**
     *  @notice The pre-calculated keccak256 hash of the SECRET, used for phase transition testing.
     */
    bytes32 public committedHash;

    /**
     * @notice Configures the testing environment before the execution of each test case.
     * @dev Utilizes Foundry cheatcodes (makeAddr, deal, prank) to initialize state.
     * Deploys the Lottery contract with the designated owner and ticket parameters.
     */
    function setUp() public virtual {
        owner = makeAddr("owner");
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");

        vm.deal(player1, 10 ether);
        vm.deal(player2, 10 ether);

        committedHash = keccak256(abi.encodePacked(SECRET));

        vm.prank(owner);
        lottery = new Lottery(TICKET_PRICE, MAX_TICKETS);
    }
}
