// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Base Lottery Test Setup
 * @notice Provides the foundational state, accounts, and deployment logic for all Lottery test suites.
 * @dev Inherits from forge-std/Test.sol. This contract is meant to be inherited, not run directly.
 */
contract BaseLotteryTest is Test {
    /// @notice The main Lottery contract instance
    Lottery public lottery;

    /// @notice Address simulating the contract deployer and owner
    address public owner;

    /// @notice Address simulating the first participating player
    address public player1;

    /// @notice Address simulating the second participating player
    address public player2;

    /// @notice Standardized ticket price for the test suite
    uint256 public constant TICKET_PRICE = 0.01 ether;

    /// @notice The raw secret value used for the commit-reveal scheme
    // casting to 'bytes32' is safe because the string "superSecretValue" is 16 bytes, well under the 32-byte limit
    // forge-lint: disable-next-line(unsafe-typecast)
    bytes32 public constant SECRET = bytes32("superSecretValue");

    /// @notice The pre-computed keccak256 hash of the secret value
    bytes32 public committedHash;

    /**
     * @notice Initializes the testing environment before each test runs.
     * @dev Generates addresses, funds them with ETH, computes the commit hash off-chain, and deploys the contract.
     */
    function setUp() public virtual {
        owner = makeAddr("owner");
        player1 = makeAddr("player1");
        player2 = makeAddr("player2");

        // Fund players
        vm.deal(player1, 1 ether);
        vm.deal(player2, 1 ether);

        // Compute the commit hash off-chain (simulated)
        committedHash = keccak256(abi.encodePacked(SECRET));

        // Deploy as owner
        vm.prank(owner);
        lottery = new Lottery(TICKET_PRICE);
    }
}
