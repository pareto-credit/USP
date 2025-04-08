// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { ParetoDollarQueue, IParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
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
    // Deploy ParetoDollar with transparent proxy
    // check https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades for more info
    par = ParetoDollar(Upgrades.deployTransparentProxy(
      "ParetoDollar.sol",
      TL_MULTISIG, // INITIAL_OWNER_ADDRESS_FOR_PROXY_ADMIN,
      abi.encodeCall(
        ParetoDollar.initialize, (
          TL_MULTISIG,
          HYPERNATIVE_PAUSER,
          // Precompute the address of the ParetoDollarQueue contract
          // - first contract is the ParetoDollar implementation (nonce)
          // - second contract is the ParetoDollar proxy (nonce + 1)
          // - third contract is the ParetoDollarQueue implementation (nonce + 2)
          // - fourth contract is the ParetoDollarQueue proxy (nonce + 3)
          vm.computeCreateAddress(DEPLOYER, vm.getNonce(DEPLOYER) + 3)
        )
      )
    ));

    address[] memory managersQueue = new address[](1);
    managersQueue[0] = TL_MULTISIG;
    // Deploy ParetoDollarQueue with transparent proxy
    queue = ParetoDollarQueue(Upgrades.deployTransparentProxy(
      "ParetoDollarQueue.sol",
      TL_MULTISIG,
      abi.encodeCall(
        ParetoDollarQueue.initialize, (
          TL_MULTISIG,
          HYPERNATIVE_PAUSER,
          address(par),
          // Precompute the address of the ParetoDollarStaking contract
          // - first contract is the ParetoDollarQueue implementation (nonce)
          // - second contract is the ParetoDollarQueue proxy (nonce + 1)
          // - third contract is the ParetoDollarStaking implementation (nonce + 2)
          // - fourth contract is the ParetoDollarStaking proxy (nonce + 3)
          vm.computeCreateAddress(DEPLOYER, vm.getNonce(DEPLOYER) + 3),
          managersQueue
        )
      )
    ));

    // Deploy ParetoDollarStaking with transparent proxy
    sPar = ParetoDollarStaking(Upgrades.deployTransparentProxy(
      "ParetoDollarStaking.sol",
      TL_MULTISIG,
      abi.encodeCall(
        ParetoDollarStaking.initialize, (
          address(par),
          TL_MULTISIG,
          HYPERNATIVE_PAUSER,
          address(queue)
        )
      )
    ));

    // add fasanara yield source
    IParetoDollarQueue.Method[] memory allowedMethods = new IParetoDollarQueue.Method[](4);
    allowedMethods[0] = IParetoDollarQueue.Method(DEPOSIT_AA_SIG, 0);
    allowedMethods[1] = IParetoDollarQueue.Method(WITHDRAW_AA_SIG, 1); // this will *request* a redeem
    allowedMethods[2] = IParetoDollarQueue.Method(CLAIM_REQ_SIG, 2);
    allowedMethods[3] = IParetoDollarQueue.Method(CLAIM_INSTANT_REQ_SIG, 2);
    uint256 maxCap = 100_000_000 * 1e6; // 100M USDC
    queue.addYieldSource(FAS_USDC_CV, USDC, AA_FAS_USDC_CV, maxCap, allowedMethods, 1);

    // add sky.money sUSDS yield source
    allowedMethods = new IParetoDollarQueue.Method[](3);
    allowedMethods[0] = IParetoDollarQueue.Method(DEPOSIT_4626_SIG, 0);
    allowedMethods[1] = IParetoDollarQueue.Method(WITHDRAW_4626_SIG, 2);
    allowedMethods[2] = IParetoDollarQueue.Method(REDEEM_4626_SIG, 2);
    maxCap = 100_000_000 * 1e18; // 100M USDS
    queue.addYieldSource(SUSDS, USDS, SUSDS, maxCap, allowedMethods, 2);

    // add sky.money USDS-USDC PSM as a "yield source" with 0 max cap (ie unlimited)
    // we are approving only USDS to be swapped for USDC when calling `addYieldSource` the opposite is done 
    // directly in the `initialize`
    // "Gem" is USDC here
    allowedMethods = new IParetoDollarQueue.Method[](2);
    allowedMethods[0] = IParetoDollarQueue.Method(BUY_GEM_SIG, 1);
    allowedMethods[1] = IParetoDollarQueue.Method(SELL_GEM_SIG, 1);
    queue.addYieldSource(USDS_USDC_PSM, USDC, USDS, 0, allowedMethods, 0);

    // Set keyring params
    par.setKeyringParams(KEYRING_WHITELIST, KEYRING_POLICY);

    // Add USDC collateral
    par.addCollateral(
      USDC,
      IERC20Metadata(USDC).decimals(),
      USDC_FEED,
      USDC_FEED_DECIMALS
    );

    // Add USDT collateral
    par.addCollateral(
      USDT,
      IERC20Metadata(USDT).decimals(),
      USDT_FEED,
      USDT_FEED_DECIMALS
    );

    // Add USDS collateral
    par.addCollateral(
      USDS,
      IERC20Metadata(USDS).decimals(),
      USDS_FEED,
      USDS_FEED_DECIMALS
    );

    // transfer ownership of ParetoDollar to TL_MULTISIG
    par.transferOwnership(TL_MULTISIG);
    // transfer ownership of ParetoDollarQueue to TL_MULTISIG
    queue.transferOwnership(TL_MULTISIG);

    if (shouldLog) {
      console.log('ParetoDollar deployed at:', address(par));
      // Get the implementation address of the proxy for ParetoDollar
      address implAddr = Upgrades.getImplementationAddress(address(par));
      console.log('Proxy implementation address for ParetoDollar:', implAddr);
      // Get the admin address of the proxy for ParetoDollar
      address parAdmin = Upgrades.getAdminAddress(address(par));
      console.log('Proxy admin address for ParetoDollar:', parAdmin);
      console.log();

      console.log('ParetoDollarQueue deployed at:', address(queue));
      // Get the implementation address of the proxy for ParetoDollarQueue
      address queueImplAddr = Upgrades.getImplementationAddress(address(queue));
      console.log('Proxy implementation address for ParetoDollarQueue:', queueImplAddr);
      // Get the admin address of the proxy for ParetoDollarQueue
      address queueAdmin = Upgrades.getAdminAddress(address(queue));
      console.log('Proxy admin address for ParetoDollarQueue:', queueAdmin);
      console.log();

      console.log('ParetoDollarStaking deployed at:', address(sPar));
      // Get the implementation address of the proxy for ParetoDollarStaking
      address sImplAddr = Upgrades.getImplementationAddress(address(sPar));
      console.log('Proxy implementation address for ParetoDollarStaking:', sImplAddr);
      // Get the admin address of the proxy for ParetoDollarStaking
      address sParAdmin = Upgrades.getAdminAddress(address(sPar));
      console.log('Proxy admin address for ParetoDollarStaking:', sParAdmin);
      console.log();

      console.log('IMPORTANT: Queue contract should be whitelisted on each credit vault');
    }
  }

  modifier broadcast() {
    vm.startBroadcast();
    _;
    vm.stopBroadcast();
  }
}
