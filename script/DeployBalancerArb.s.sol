// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { BalancerArb } from "../src/BalancerArb.sol";

contract DeployBalancerArb is Script {
  string public constant network = "mainnet";

  // forge build && forge script ./script/DeployBalancerArb.s.sol --ledger --broadcast --optimize --optimizer-runs 100000 --sender "0xE5Dab8208c1F4cce15883348B72086dBace3e64B" --slow -vvv
  function run() public {
    vm.createSelectFork(network);
    console2.log('Deploying in ', network);
    
    vm.startBroadcast();
    BalancerArb arb = new BalancerArb();
    vm.label(address(arb), "BalancerArb");
    console2.log('BalancerArb deployed at:', address(arb));
    vm.stopBroadcast();
  }
}
