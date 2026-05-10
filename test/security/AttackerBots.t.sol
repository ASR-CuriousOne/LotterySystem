// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "../base/BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

/**
 * @title Veritas Security & Vulnerability Test Suite
 * @author BitBoyz Team
 * @notice Stress tests the Tier 1 Lottery contract against common smart contract attack vectors.
 * @dev Inherits from BaseLotteryTest. This suite validates the protocol's integrity against
 * commitment tampering, administrative Denial of Service (DoS), miner-led block manipulation,
 * and recursive withdrawal attacks.
 */
contract AttackerBotsTest is BaseLotteryTest {
    /**
     * @notice An instance of a malicious contract designed to exploit the claimPrize function.
     */
    GreedyReentrantBot public reentrancyBot;

    /**
     * @notice Initializes the security sandbox and provisions the malicious actor.
     * @dev Deploys the GreedyReentrantBot and provides it with 10 ETH to facilitate entry testing.
     */
    function setUp() public override {
        super.setUp();
        reentrancyBot = new GreedyReentrantBot(lottery);
        vm.deal(address(reentrancyBot), 10 ether);
    }

    /**
     * @notice Verifies that the owner is cryptographically locked into their secret once committed.
     * @dev Ensures that the transition to the 'Committed' phase is final and prevents the owner
     * from "front-running" a loss by attempting to overwrite the hash with a different secret.
     */
    function testBot_OwnerCannotTamperWithCommitment() public {
        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        bytes32 fakeHash = keccak256(abi.encodePacked("fakeSecret"));

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.expectRevert("Sale not closed");
        vm.prank(owner);
        lottery.commitHash(fakeHash);
    }

    /**
     * @notice Highlights the centralized risk of owner-led draw systems.
     * @dev Demonstrates that if an owner refuses to call revealAndDraw(), participants' funds
     * remain locked, illustrating a potential administrative Denial of Service (DoS) vector.
     */
    function testBot_OwnerCanDenyServiceByWithholdingSecret() public {
        vm.deal(owner, 10 ether);

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.expectRevert("Winner not drawn yet");
        vm.prank(player1);
        lottery.claimPrize();
    }

    /**
     * @notice Simulates a miner-attacker (MEV) manipulating block properties to influence outcomes.
     * @dev This test iterates through future block numbers until it finds one where the
     * keccak256(SECRET, block.number) formula selects the attacker. It then uses vm.roll
     * to simulate the miner's ability to "hold" a block until the hash is favorable.
     */
    function testBot_MinerBlockManipulation() public {
        address minerAttacker = makeAddr("minerAttacker");
        vm.deal(minerAttacker, 10 ether);

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(minerAttacker);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        (,, uint256 pCount,,) = lottery.getLotteryInfo();

        uint256 i = 0;
        while (true) {
            uint256 simulatedWinnerIndex = uint256(keccak256(abi.encodePacked(SECRET, block.number + i))) % pCount;

            if (lottery.participants(simulatedWinnerIndex) == minerAttacker) {
                vm.roll(block.number + i);
                break;
            }
            i++;
        }

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        assertEq(lottery.winner(), minerAttacker);
    }

    /**
     * @notice Validates the effectiveness of the ReentrancyGuard and CEI pattern.
     * @dev Simulates a recursive withdrawal attack. Proves that the second call to claimPrize
     * within the same transaction results in a revert, protecting the prize pool from drainage.
     */
    function testBot_GreedyReentrancyAttempt() public {
        reentrancyBot.buyTicket();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.roll(block.number + 1);

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);

        assertEq(lottery.winner(), address(reentrancyBot));

        vm.expectRevert();
        reentrancyBot.claim();
    }
}

/**
 * @title Veritas Malicious Reentrancy Actor
 * @author BitBoyz Team
 * @notice A purpose-built attacking contract designed to execute a recursive claimPrize attack.
 * @dev Implements a state-tracked receive() function to attempt re-entry into the target
 * contract during the low-level ETH transfer phase.
 */
contract GreedyReentrantBot {
    /**
     * @notice The specific Lottery contract targeted by the reentrancy exploit.
     */
    Lottery public target;

    /**
     * @notice Tracks the recursion depth to prevent infinite loops during the attack.
     */
    uint256 public attackCount;

    /**
     * @notice Links the bot to the target lottery instance.
     * @param _target The address of the Lottery contract to be attacked.
     */
    constructor(Lottery _target) {
        target = _target;
    }

    /**
     * @notice Enters the bot into the lottery as a legitimate participant.
     */
    function buyTicket() external {
        target.buyTicket{value: 0.01 ether}();
    }

    /**
     * @notice Triggers the initial withdrawal attempt to kickstart the reentrancy loop.
     */
    function claim() external {
        target.claimPrize();
    }

    /**
     * @notice The attack vector; attempts to call claimPrize again before the first call finishes.
     * @dev Triggered when the target contract sends ETH via a low-level call.
     */
    receive() external payable {
        if (attackCount == 0) {
            attackCount++;
            target.claimPrize();
        }
    }
}
