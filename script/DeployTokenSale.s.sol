// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Script, console} from "forge-std/Script.sol";
import {TokenSale} from "../src/TokenSale.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";

/**
 * @title DeployTokenSale
 * @dev Deployment script for TokenSale contract with proxy
 */
contract DeployTokenSale is Script {
    function run() public returns (TokenSale tokenSale) {
        vm.startBroadcast();

        // Get deployment parameters from environment
        address baseToken = vm.envAddress("BASE_TOKEN");
        address paymentRecipient = vm.envAddress("PAYMENT_RECIPIENT");
        address admin = vm.envAddress("ADMIN");

        console.log("Deploying TokenSale contract with proxy...");
        console.log("Base Token:", baseToken);
        console.log("Payment Recipient:", paymentRecipient);
        console.log("Admin:", admin);

        // Deploy transparent proxy
        address proxyAddress = Upgrades.deployTransparentProxy(
            "TokenSale.sol:TokenSale",
            admin, // Proxy admin
            abi.encodeCall(
                TokenSale.initialize,
                (baseToken, paymentRecipient, admin)
            )
        );

        tokenSale = TokenSale(proxyAddress);

        console.log("TokenSale deployed at:", proxyAddress);
        address implementationAddress = Upgrades.getImplementationAddress(proxyAddress);
        console.log("Implementation address:", implementationAddress);

        vm.stopBroadcast();
    }
}
