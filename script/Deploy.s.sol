// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Veritas Lottery Deployment Script
 * @author BitBoyz Team
 * @notice A Foundry script to automate the deployment and initial configuration of the Lottery contract.
 * @dev Utilizes the Forge Scripting engine to sign and broadcast transactions to the target network.
 */
contract Deploy is Script {
    /**
     * @notice Orchestrates the deployment of the Tier 1 Lottery contract.
     * @dev Executes on-chain transactions via vm.startBroadcast() and logs deployment artifacts to the terminal.
     * Sets the standardized TICKET_PRICE to 0.01 ETH and MAX_TICKETS to 100 for the production instance.
     * @return The instance of the newly deployed Lottery contract.
     */
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
