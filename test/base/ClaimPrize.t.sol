// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseLotteryTest} from "./BaseLottery.t.sol";
import {Lottery} from "../../src/Lottery.sol";

contract ClaimPrizeTest is BaseLotteryTest {
    function setUp() public override {
        super.setUp();

        vm.prank(player1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(owner);
        lottery.closeSale();

        vm.prank(owner);
        lottery.commitHash(committedHash);

        vm.prank(owner);
        lottery.revealAndDraw(SECRET);
    }

    function testRevertIfNonWinnerClaimsPrize() public {
        vm.expectRevert("Caller is not the winner");
        vm.prank(player2);
        lottery.claimPrize();
    }

    function testRevertIfClaimBeforeDrawn() public {
        vm.prank(owner);
        Lottery freshLottery = new Lottery(TICKET_PRICE, MAX_TICKETS);

        vm.prank(player1);
        vm.expectRevert("Winner not drawn yet");
        freshLottery.claimPrize();
    }

    function testRevertIfPrizeAlreadyClaimed() public {
        vm.prank(player1);
        lottery.claimPrize();

        vm.prank(player1);
        vm.expectRevert("Prize already claimed");
        lottery.claimPrize();
    }

    function testRevertIfTransferFailed() public {
        vm.prank(owner);
        Lottery freshLottery = new Lottery(TICKET_PRICE, MAX_TICKETS);

        RejectETH rejector = new RejectETH();
        vm.deal(address(rejector), TICKET_PRICE);
        rejector.buy{value: TICKET_PRICE}(freshLottery);

        vm.prank(owner);
        freshLottery.closeSale();

        vm.prank(owner);
        freshLottery.commitHash(committedHash);

        vm.prank(owner);
        freshLottery.revealAndDraw(SECRET);

        vm.expectRevert("Transfer failed");
        rejector.claim(freshLottery);
    }
}

contract RejectETH {
    function buy(Lottery _lottery) external payable {
        _lottery.buyTicket{value: msg.value}();
    }

    function claim(Lottery _lottery) external {
        _lottery.claimPrize();
    }
}
