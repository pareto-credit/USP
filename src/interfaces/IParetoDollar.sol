// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IParetoDollar {
  error CollateralNotAllowed();
  error InvalidOraclePrice();
  error CollateralPriceBelowThreshold();
  error InvalidData();
  error AlreadyInitialized();
  error NotAllowed();

  event CollateralAdded(
    address indexed token,
    address priceFeed,
    uint8 tokenDecimals,
    uint8 priceFeedDecimals
  );
  event CollateralRemoved(address indexed token);
  event Minted(address indexed user, address indexed collateralToken, uint256 collateralAmount, uint256 uspminted);
  event Redeemed(address indexed user, uint256 indexed epoch, uint256 uspBurned);
  event RedeemRequested(address indexed user, uint256 indexed epoch, uint256 uspBurned);

  /// @notice Information about each allowed collateral token.
  struct CollateralInfo {
    bool allowed;
    address priceFeed;               // Primary oracle address
    uint8 tokenDecimals;             // Collateral token decimals (e.g., 6 for USDC, 18 for DAI)
    uint8 priceFeedDecimals;         // Primary oracle decimals (e.g., 8 for many Chainlink feeds)
  }

  function getCollateralInfo(address collateralToken) external view returns (CollateralInfo memory);
  function getCollaterals() external view returns (address[] memory);
  function getOraclePrice(address token) external view returns (uint256 price);
  function mint(address collateralToken, uint256 amount) external returns (uint256);
  function requestRedeem(uint256 uspAmount) external;
  function claimRedeemRequest(uint256 epoch) external returns(uint256);
  function isWalletAllowed(address _user) external view returns (bool);
  function mintForQueue(uint256 amount) external;
}