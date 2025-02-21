// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { IParetoDollar } from "../src/interfaces/IParetoDollar.sol";
import { DeployScript, Constants } from "../script/Deploy.s.sol";

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
    assertEq(par.name(), 'Pareto synthetic dollar USP', 'name is wrong');
    assertEq(par.symbol(), 'USP', 'symbol is wrong');
    assertEq(par.owner(), DEPLOYER, 'owner is wrong');

    assertEq(par.totalSupply(), 0, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');

    assertEq(par.keyring(), KEYRING_WHITELIST, 'keyring is wrong');
    assertEq(par.keyringPolicyId(), KEYRING_POLICY, 'keyring policy is wrong');

    IParetoDollar.CollateralInfo memory usdcCollateral = par.getCollateralInfo(USDC);
    
    assertEq(usdcCollateral.allowed, true, 'USDC collateral should be allowed');
    assertEq(usdcCollateral.priceFeed, USDC_FEED, 'USDC priceFeed should be set');
    assertEq(usdcCollateral.fallbackPriceFeed, USDC_FALLBACK_FEED, 'USDC fallbackPriceFeed should be set');
    assertEq(usdcCollateral.tokenDecimals, 6, 'USDC should have 6 decimals');
    assertEq(usdcCollateral.priceFeedDecimals, USDT_FEED_DECIMALS, 'Price feed for USDC should have 8 decimals');
    assertEq(usdcCollateral.fallbackPriceFeedDecimals, USDT_FALLBACK_FEED_DECIMALS, 'Fallback price feed for USDC should have 8 decimals');
  
    IParetoDollar.CollateralInfo memory usdtCollateral = par.getCollateralInfo(USDT);

    assertEq(usdtCollateral.allowed, true, 'USDT collateral should be allowed');
    assertEq(usdtCollateral.priceFeed, USDT_FEED, 'USDT priceFeed should be set');
    assertEq(usdtCollateral.fallbackPriceFeed, USDT_FALLBACK_FEED, 'USDT fallbackPriceFeed should be set');
    assertEq(usdtCollateral.tokenDecimals, 6, 'USDT should have 6 decimals');
    assertEq(usdtCollateral.priceFeedDecimals, USDT_FEED_DECIMALS, 'Price feed for USDT should have 8 decimals');
    assertEq(usdtCollateral.fallbackPriceFeedDecimals, USDT_FALLBACK_FEED_DECIMALS, 'Fallback price feed for USDT should have 8 decimals');
  }
}