// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { ParetoDollar } from "../src/ParetoDollar.sol";

import { BaseScript } from "./Base.s.sol";
import "forge-std/src/console.sol";

contract DeployScript is BaseScript {
  address public DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;

  function run() public broadcast {
    // forge script ./script/Deploy.s.sol \
    // --fork-url $ETH_RPC_URL \
    // --ledger \
    // --broadcast \
    // --optimize \
    // --optimizer-runs 999999 \
    // --verify \
    // --with-gas-price 5000000000 \
    // --sender "0xE5Dab8208c1F4cce15883348B72086dBace3e64B" \
    // --slow \
    // -vvv

    _deploy();
  }

  function _deploy() public returns (
    ParetoDollar par
  ) {
    // Deploy ParetoDollar
    par = new ParetoDollar();
    console.log('ParetoDollar deployed at:', address(par));
  }
}
