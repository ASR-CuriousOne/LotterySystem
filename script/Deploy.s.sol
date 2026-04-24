// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {Lottery} from "../src/Lottery.sol";

/**
 * @title Lottery Deployment Script
 * @notice Handles the broadcast and deployment of the Lottery contract.
 */
contract Deploy is Script {
    /**
     * @notice Executes the deployment sequence.
     * @dev Starts a broadcast using the CLI-provided private key, deploys the Lottery, and stops the broadcast.
     * @return The deployed Lottery contract instance.
     */
    function run() external returns (Lottery) {
        uint256 initialTicketPrice = 0.01 ether;

        vm.startBroadcast();
        Lottery lottery = new Lottery(initialTicketPrice);
        vm.stopBroadcast();

        console2.log("Lottery deployed at:", address(lottery));
        console2.log("Ticket Price (wei):", initialTicketPrice);

        return lottery;
    }
}
