// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IParetoDollar {
  error CollateralNotAllowed();
  error InvalidOraclePrice();
  error CollateralPriceBelowThreshold();
  error InsufficientCollateral();
  error InvalidData();
  error AlreadyInitialized();
  error NotAllowed();

  event CollateralAdded(
    address indexed token,
    address priceFeed,
    address fallbackPriceFeed,
    uint8 tokenDecimals,
    uint8 priceFeedDecimals,
    uint8 fallbackPriceFeedDecimals
  );
  event CollateralRemoved(address indexed token);
  event Minted(address indexed user, address indexed collateralToken, uint256 collateralAmount, uint256 uspminted);
  event Redeemed(address indexed user, address indexed collateralToken, uint256 uspburned, uint256 collateralReturned);

  /// @notice Information about each allowed collateral token.
  struct CollateralInfo {
    bool allowed;
    address priceFeed;               // Primary oracle address
    address fallbackPriceFeed;       // Optional fallback oracle address
    uint8 tokenDecimals;             // Collateral token decimals (e.g., 6 for USDC, 18 for DAI)
    uint8 priceFeedDecimals;         // Primary oracle decimals (e.g., 8 for many Chainlink feeds)
    uint8 fallbackPriceFeedDecimals; // Fallback oracle decimals
  }

  function getCollateralInfo(address collateralToken) external view returns (CollateralInfo memory);
  function getOraclePrice(address token) external view returns (uint256 price);
  function mint(address collateralToken, uint256 amount) external;
  function redeem(address collateralToken, uint256 uspAmount) external;
  function isWalletAllowed(address _user) external view returns (bool);
}