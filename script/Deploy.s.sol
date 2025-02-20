// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ParetoDollar } from "../src/ParetoDollar.sol";
import { Constants } from "../src/Constants.sol";

contract DeployScript is Script, Constants {
  function run() public broadcast {
    _deploy();
  }

  function _deploy() public returns (ParetoDollar par) {
    // Deploy ParetoDollar with transparent proxy
    // check https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades for more info
    address proxy = Upgrades.deployTransparentProxy(
      "ParetoDollar.sol",
      DEPLOYER, // INITIAL_OWNER_ADDRESS_FOR_PROXY_ADMIN,
      abi.encodeCall(ParetoDollar.initialize, (DEPLOYER))
    );
    par = ParetoDollar(proxy);

    console.log('ParetoDollar deployed at:', address(par));
    // Get the implementation address of the proxy
    address implAddr = Upgrades.getImplementationAddress(proxy);
    console.log('Proxy implementation address:', implAddr);
    // Get the admin address of the proxy
    address proxyAdmin = Upgrades.getAdminAddress(proxy);
    console.log('Proxy admin address:', proxyAdmin);

    // Set keyring params
    par.setKeyringParams(KEYRING_WHITELIST, KEYRING_POLICY);

    // Add USDC collateral
    par.addCollateral(
      USDC,
      USDC_FEED_DECIMALS,
      USDC_FEED,
      IERC20Metadata(USDC).decimals(),
      USDC_FALLBACK_FEED,
      USDC_FALLBACK_FEED_DECIMALS
    );

    // Add USDT collateral
    par.addCollateral(
      USDT,
      USDT_FEED_DECIMALS,
      USDT_FEED,
      IERC20Metadata(USDT).decimals(),
      USDT_FALLBACK_FEED,
      USDT_FALLBACK_FEED_DECIMALS
    );
  }

  modifier broadcast() {
    vm.startBroadcast();
    _;
    vm.stopBroadcast();
  }
}
