// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { Script } from "forge-std/src/Script.sol";
import "forge-std/src/console.sol";

contract DeployScript is Script {
  address public DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;

  function run() public broadcast {
    _deploy();
  }

  function _deploy() public returns (ParetoDollar par) {
    // Deploy ParetoDollar
    par = new ParetoDollar();
    console.log('ParetoDollar deployed at:', address(par));
  }

  modifier broadcast() {
    vm.startBroadcast();
    _;
    vm.stopBroadcast();
  }
}
