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

contract DeployScriptTest is Script, Constants {
  string public constant BUILD_INFO_DIR = "old-build-info/";
  string public constant network = "optimism";

  function run() public {
    vm.createSelectFork(network);
    vm.startBroadcast();
    _deploy(true);
    vm.stopBroadcast();
  }

  function _deploy(bool shouldLog) public returns (
    ParetoDollar par,
    ParetoDollarStaking sPar,
    ParetoDollarQueue queue
  ) {
    console.log('Deploying in ', network);

    // Deploy ParetoDollar with transparent proxy
    // check https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades for more info
    par = ParetoDollar(Upgrades.deployTransparentProxy(
      "ParetoDollar.sol",
      DEPLOYER, // INITIAL_OWNER_ADDRESS_FOR_PROXY_ADMIN,
      abi.encodeCall(
        ParetoDollar.initialize, (
          DEPLOYER,
          DEPLOYER,
          // Precompute the address of the ParetoDollarQueue contract
          // - first contract is the ParetoDollar implementation (nonce)
          // - second contract is the ParetoDollar proxy + admin (nonce + 1)
          // - third contract is the ParetoDollarQueue implementation (nonce + 2)
          // - fourth contract is the ParetoDollarQueue proxy + admin (nonce + 3)
          vm.computeCreateAddress(DEPLOYER, vm.getNonce(DEPLOYER) + 3)
        )
      )
    ));

    address[] memory managersQueue = new address[](1);
    managersQueue[0] = 0xf122860965303fdcdB986C53f35BDfC0e331c044;
    // Deploy ParetoDollarQueue with transparent proxy
    queue = ParetoDollarQueue(Upgrades.deployTransparentProxy(
      "ParetoDollarQueue.sol",
      DEPLOYER,
      abi.encodeCall(
        ParetoDollarQueue.initialize, (
          DEPLOYER,
          DEPLOYER,
          address(par),
          // Precompute the address of the ParetoDollarStaking contract
          // - first contract is the ParetoDollarQueue implementation (nonce)
          // - second contract is the ParetoDollarQueue proxy + admin (nonce + 1)
          // - third contract is the ParetoDollarStaking implementation (nonce + 2)
          // - fourth contract is the ParetoDollarStaking proxy + admin (nonce + 3)
          vm.computeCreateAddress(DEPLOYER, vm.getNonce(DEPLOYER) + 3),
          managersQueue
        )
      )
    ));

    // Deploy ParetoDollarStaking with transparent proxy
    sPar = ParetoDollarStaking(Upgrades.deployTransparentProxy(
      "ParetoDollarStaking.sol",
      DEPLOYER,
      abi.encodeCall(
        ParetoDollarStaking.initialize, (
          address(par),
          DEPLOYER,
          DEPLOYER,
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

    par.setKeyringParams(KEYRING_WHITELIST, KEYRING_POLICY);

    // Add USDC collateral
    par.addCollateral(USDC, USDC_FEED, 24 hours);

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
      console.log(string(abi.encodePacked('IMPORTANT: Move new build info from ', BUILD_INFO_DIR, ' to (replace old file) ', string(abi.encodePacked(BUILD_INFO_DIR, network)))));
    }
  }
}
