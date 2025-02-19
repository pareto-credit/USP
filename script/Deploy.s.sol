// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { Script } from "forge-std/src/Script.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "forge-std/src/console.sol";

contract DeployScript is Script {
  address public DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  // TODO confirm values for keyring whitelist and policy
  address public KEYRING_WHITELIST = 0x6351370a1c982780Da2D8c85DfedD421F7193Fa5;
  uint256 public KEYRING_POLICY = 4;
  // USDC feed data
  address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public USDC_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  uint8 public USDC_FEED_DECIMALS = 8;
  address public USDC_FALLBACK_FEED = address(0);
  uint8 public USDC_FALLBACK_FEED_DECIMALS = 0;
  // USDT feed data
  address public USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address public USDT_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  uint8 public USDT_FEED_DECIMALS = 8;
  address public USDT_FALLBACK_FEED = address(0);
  uint8 public USDT_FALLBACK_FEED_DECIMALS = 0;

  function run() public broadcast {
    _deploy();
  }

  function _deploy() public returns (ParetoDollar par) {
    // Deploy ParetoDollar
    par = new ParetoDollar();
    console.log('ParetoDollar deployed at:', address(par));

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
