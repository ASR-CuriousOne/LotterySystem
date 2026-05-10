// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "../base/BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

contract AttackerBotsTest is BaseLotteryTest {
    GreedyReentrantBot public reentrancyBot;

    function setUp() public override {
        super.setUp();
        reentrancyBot = new GreedyReentrantBot(lottery);
        vm.deal(address(reentrancyBot), 10 ether);
    }

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

contract GreedyReentrantBot {
    Lottery public target;
    uint256 public attackCount;

    constructor(Lottery _target) {
        target = _target;
    }

    function buyTicket() external {
        target.buyTicket{value: 0.01 ether}();
    }

    function claim() external {
        target.claimPrize();
    }

    receive() external payable {
        if (attackCount == 0) {
            attackCount++;
            target.claimPrize();
        }
    }
}
