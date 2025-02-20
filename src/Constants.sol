// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Constants {
  address public constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  
  // TODO confirm values for keyring whitelist and policy
  address public constant KEYRING_WHITELIST = 0x6351370a1c982780Da2D8c85DfedD421F7193Fa5;
  uint256 public constant KEYRING_POLICY = 4;
  // USDC feed data
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public constant USDC_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  uint8 public constant USDC_FEED_DECIMALS = 8;
  address public constant USDC_FALLBACK_FEED = address(0);
  uint8 public constant USDC_FALLBACK_FEED_DECIMALS = 0;
  // USDT feed data
  address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address public constant USDT_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  uint8 public constant USDT_FEED_DECIMALS = 8;
  address public constant USDT_FALLBACK_FEED = address(0);
  uint8 public constant USDT_FALLBACK_FEED_DECIMALS = 0;
}