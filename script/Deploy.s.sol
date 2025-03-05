// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { Constants } from "../src/Constants.sol";

contract DeployScript is Script, Constants {
  function run() public broadcast {
    _deploy(true);
  }

  function _deploy(bool shouldLog) public returns (ParetoDollar par, ParetoDollarStaking sPar) {
    // Deploy ParetoDollar with transparent proxy
    // check https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades for more info
    address proxy = Upgrades.deployTransparentProxy(
      "ParetoDollar.sol",
      TL_MULTISIG, // INITIAL_OWNER_ADDRESS_FOR_PROXY_ADMIN,
      abi.encodeCall(ParetoDollar.initialize, ())
    );
    par = ParetoDollar(proxy);

    address[] memory managers = new address[](1);
    managers[0] = TL_MULTISIG;

    // Deploy ParetoDollarStaking with transparent proxy
    address sProxy = Upgrades.deployTransparentProxy(
      "ParetoDollarStaking.sol",
      TL_MULTISIG,
      abi.encodeCall(
        ParetoDollarStaking.initialize, (
          address(par),
          TL_MULTISIG,
          HYPERNATIVE_PAUSER,
          managers
        )
      )
    );
    sPar = ParetoDollarStaking(sProxy);

    if (shouldLog) {
      console.log('ParetoDollar deployed at:', address(par));
      // Get the implementation address of the proxy for ParetoDollar
      address implAddr = Upgrades.getImplementationAddress(proxy);
      console.log('Proxy implementation address for ParetoDollar:', implAddr);
      // Get the admin address of the proxy for ParetoDollar
      address proxyAdmin = Upgrades.getAdminAddress(proxy);
      console.log('Proxy admin address for ParetoDollar:', proxyAdmin);

      console.log('ParetoDollarStaking deployed at:', address(sPar));
      // Get the implementation address of the proxy for ParetoDollarStaking
      address sImplAddr = Upgrades.getImplementationAddress(sProxy);
      console.log('Proxy implementation address for ParetoDollarStaking:', sImplAddr);
      // Get the admin address of the proxy for ParetoDollarStaking
      address sProxyAdmin = Upgrades.getAdminAddress(sProxy);
      console.log('Proxy admin address for ParetoDollarStaking:', sProxyAdmin);
    }

    // Set keyring params
    par.setKeyringParams(KEYRING_WHITELIST, KEYRING_POLICY);

    // Add USDC collateral
    par.addCollateral(
      USDC,
      IERC20Metadata(USDC).decimals(),
      USDC_FEED,
      USDC_FEED_DECIMALS,
      USDC_FALLBACK_FEED,
      USDC_FALLBACK_FEED_DECIMALS
    );

    // Add USDT collateral
    par.addCollateral(
      USDT,
      IERC20Metadata(USDT).decimals(),
      USDT_FEED,
      USDT_FEED_DECIMALS,
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
