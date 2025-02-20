// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { DeployScript } from "../script/Deploy.s.sol";

contract TestParetoDollar is Test, DeployScript {
  ParetoDollar par;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par) = _deploy();
    vm.stopPrank();

    skip(100);
  }

  function testInitialize() external view {
    assertEq(par.totalSupply(), 0, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');
  }
}