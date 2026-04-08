// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";

contract BaseLotteryTest is Test {
    Lottery public lottery;

    address public owner;
    address public player1;
    address public player2;

    uint256 public constant TICKET_PRICE = 0.01 ether;
    bytes32 public constant SECRET = bytes32("superSecretValue");
    bytes32 public committedHash;

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
