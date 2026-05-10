// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";

contract Deploy is Script {
    function run() external returns (Lottery) {
        uint256 ticketPrice = 0.01 ether;
        uint256 maxTickets = 100;

        vm.startBroadcast();
        Lottery lottery = new Lottery(ticketPrice, maxTickets);
        vm.stopBroadcast();

        console2.log("Lottery deployed at:", address(lottery));
        console2.log("Ticket Price (wei):", ticketPrice);
        console2.log("Max Tickets:", maxTickets);

        return lottery;
    }
}
