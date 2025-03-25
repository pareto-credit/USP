// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { ParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { Constants } from "../src/Constants.sol";

contract DeployScript is Script, Constants {
  function run() public broadcast {
    _deploy(true);
  }

  function _deploy(bool shouldLog) public returns (
    ParetoDollar par,
    ParetoDollarStaking sPar,
    ParetoDollarQueue queue
  ) {
    // Precompute the address of the ParetoDollarQueue contract
    // - first contract deployed is the ProxyAdmin
    // - second contract is the ParetoDollar implementation
    // - third contract is the ParetoDollar proxy
    address queueAddr = vm.computeCreateAddress(DEPLOYER, vm.getNonce(DEPLOYER) + 3);

    // Deploy ParetoDollar with transparent proxy
    // check https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades for more info
    address proxy = Upgrades.deployTransparentProxy(
      "ParetoDollar.sol",
      TL_MULTISIG, // INITIAL_OWNER_ADDRESS_FOR_PROXY_ADMIN,
      abi.encodeCall(
        ParetoDollar.initialize, (
          TL_MULTISIG,
          HYPERNATIVE_PAUSER,
          queueAddr
        )
      )
    );
    par = ParetoDollar(proxy);

    // Deploy ParetoDollarQueue with transparent proxy
    address[] memory managersQueue = new address[](1);
    managersQueue[0] = TL_MULTISIG;
    address queueProxy = Upgrades.deployTransparentProxy(
      "ParetoDollarQueue.sol",
      TL_MULTISIG,
      abi.encodeCall(
        ParetoDollarQueue.initialize, (
          TL_MULTISIG,
          HYPERNATIVE_PAUSER,
          address(par),
          managersQueue
        )
      )
    );
    queue = ParetoDollarQueue(queueProxy);

    // add fasanara yield source with 0 max cap (ie unlimited)
    bytes4[] memory allowedMethods = new bytes4[](4);
    allowedMethods[0] = DEPOSIT_AA_SIG;
    allowedMethods[1] = WITHDRAW_AA_SIG;
    allowedMethods[2] = CLAIM_REQ_SIG;
    allowedMethods[3] = CLAIM_INSTANT_REQ_SIG;
    uint256 maxCap = 100_000_000 * 1e6; // 100M USDC
    queue.addYieldSource(FAS_USDC_CV, USDC, AA_FAS_USDC_CV, maxCap, allowedMethods);

    // Deploy ParetoDollarStaking with transparent proxy
    address[] memory managers = new address[](1);
    managers[0] = TL_MULTISIG;
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

    // transfer ownership of ParetoDollar to TL_MULTISIG
    par.transferOwnership(TL_MULTISIG);
    // transfer ownership of ParetoDollarQueue to TL_MULTISIG
    queue.transferOwnership(TL_MULTISIG);

    if (shouldLog) {
      console.log('ParetoDollar deployed at:', address(par));
      // Get the implementation address of the proxy for ParetoDollar
      address implAddr = Upgrades.getImplementationAddress(proxy);
      console.log('Proxy implementation address for ParetoDollar:', implAddr);
      // Get the admin address of the proxy for ParetoDollar
      address proxyAdmin = Upgrades.getAdminAddress(proxy);
      console.log('Proxy admin address for ParetoDollar:', proxyAdmin);

      console.log('ParetoDollarQueue deployed at:', address(queue));
      // Get the implementation address of the proxy for ParetoDollarQueue
      address queueImplAddr = Upgrades.getImplementationAddress(queueProxy);
      console.log('Proxy implementation address for ParetoDollarQueue:', queueImplAddr);
      // Get the admin address of the proxy for ParetoDollarQueue
      address queueProxyAdmin = Upgrades.getAdminAddress(queueProxy);
      console.log('Proxy admin address for ParetoDollarQueue:', queueProxyAdmin);

      console.log('ParetoDollarStaking deployed at:', address(sPar));
      // Get the implementation address of the proxy for ParetoDollarStaking
      address sImplAddr = Upgrades.getImplementationAddress(sProxy);
      console.log('Proxy implementation address for ParetoDollarStaking:', sImplAddr);
      // Get the admin address of the proxy for ParetoDollarStaking
      address sProxyAdmin = Upgrades.getAdminAddress(sProxy);
      console.log('Proxy admin address for ParetoDollarStaking:', sProxyAdmin);
      
      console.log('IMPORTANT: Queue contract should be whitelisted on each credit vault');
    }
  }

  modifier broadcast() {
    vm.startBroadcast();
    _;
    vm.stopBroadcast();
  }
}
