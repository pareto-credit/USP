// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/IPriceFeed.sol";

error CollateralNotAllowed();
error InvalidOraclePrice();
error CollateralPriceBelowThreshold();
error InsufficientCollateral();
error InvalidData();
error AlreadyInitialized();

/// @title ParetoDollar - A stablecoin minted 1:1 against approved collateral tokens
/// @notice Users can mint ParetoDollar (USP) by depositing supported collateral tokens and redeem USP for collateral tokens.
/// Minting enforces a minimum collateral price threshold (0.99 USD normalized to 18 decimals) using primary and fallback oracles,
/// while redemption does not enforce this check.
contract ParetoDollar is ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  /// @notice Information about each allowed collateral token.
  struct CollateralInfo {
    bool allowed;
    address priceFeed;               // Primary oracle address
    address fallbackPriceFeed;       // Optional fallback oracle address
    uint8 tokenDecimals;             // Collateral token decimals (e.g., 6 for USDC, 18 for DAI)
    uint8 priceFeedDecimals;         // Primary oracle decimals (e.g., 8 for many Chainlink feeds)
    uint8 fallbackPriceFeedDecimals; // Fallback oracle decimals
  }

  /// @notice Mapping from collateral token address to its info.
  mapping(address => CollateralInfo) public collateralInfo;

  /// @notice Minimum acceptable price (normalized to 18 decimals): 0.99 USD.
  uint256 public constant MIN_PRICE = 99 * 1e16; // 0.99 * 1e18

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

  /// @notice initializes the contract in the constructor so that implementation contract cannot be maliciously
  /// initialized.
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    __ERC20_init("Pareto synthetic dollar USP", "USP");
  }

  /// @notice Initializer (replaces constructor for upgradeable contracts).
  function initialize() public initializer {
    // checks if the contract is already initialized
    if (keccak256(abi.encode(symbol())) == keccak256(abi.encode("USP"))) revert AlreadyInitialized();

    __ERC20_init("Pareto synthetic dollar USP", "USP");
    __Ownable_init(msg.sender);
    __Pausable_init();
    __ReentrancyGuard_init();
  }

  /// @notice Owner can add a new collateral token.
  /// @param token The collateral token address.
  /// @param priceFeed The primary oracle address.
  /// @param tokenDecimals The decimals for the collateral token.
  /// @param priceFeedDecimals The decimals for the primary oracle.
  /// @param fallbackPriceFeed The fallback oracle address (can be address(0) if not used).
  /// @param fallbackPriceFeedDecimals The decimals for the fallback oracle.
  function addCollateral(
    address token,
    address priceFeed,
    uint8 tokenDecimals,
    uint8 priceFeedDecimals,
    address fallbackPriceFeed,
    uint8 fallbackPriceFeedDecimals
  ) external onlyOwner {
    if (token == address(0) || priceFeed == address(0)) revert InvalidData();
    collateralInfo[token] = CollateralInfo({
      allowed: true,
      priceFeed: priceFeed,
      fallbackPriceFeed: fallbackPriceFeed,
      tokenDecimals: tokenDecimals,
      priceFeedDecimals: priceFeedDecimals,
      fallbackPriceFeedDecimals: fallbackPriceFeedDecimals
    });
    emit CollateralAdded(token, priceFeed, fallbackPriceFeed, tokenDecimals, priceFeedDecimals, fallbackPriceFeedDecimals);
  }

  /// @notice Owner can remove a collateral token.
  /// @param token The collateral token address to remove.
  function removeCollateral(address token) external onlyOwner {
    if (token == address(0)) revert InvalidData();
    collateralInfo[token].allowed = false;
    emit CollateralRemoved(token);
  }

  /// @notice Mint USP by depositing an allowed collateral token.
  /// @param collateralToken The collateral token address.
  /// @param amount The amount of collateral tokens to deposit.
  /// @dev Only mints if the collateral's normalized price is at least 0.99 USD.
  function mint(address collateralToken, uint256 amount) external whenNotPaused nonReentrant {
    CollateralInfo memory info = collateralInfo[collateralToken];
    if (!info.allowed) revert CollateralNotAllowed();

    uint256 price = getOraclePrice(
      info.priceFeed,
      info.priceFeedDecimals,
      info.fallbackPriceFeed,
      info.fallbackPriceFeedDecimals
    );
    if (price < MIN_PRICE) revert CollateralPriceBelowThreshold();

    IERC20(collateralToken).safeTransferFrom(msg.sender, address(this), amount);
    uint256 scaledAmount = amount * 10 ** (18 - info.tokenDecimals);
    _mint(msg.sender, scaledAmount);
    emit Minted(msg.sender, collateralToken, amount, scaledAmount);
  }

  /// @notice Redeem USP for a specific collateral token.
  /// @param collateralToken The collateral token address.
  /// @param uspAmount The amount of USP to redeem (in 18 decimals).
  /// @dev Redemption does not enforce the price threshold.
  function redeem(address collateralToken, uint256 uspAmount) external whenNotPaused nonReentrant {
    CollateralInfo memory info = collateralInfo[collateralToken];
    if (!info.allowed) revert CollateralNotAllowed();

    _burn(msg.sender, uspAmount);
    uint256 collateralAmount = uspAmount / (10 ** (18 - info.tokenDecimals));
    if (collateralAmount > IERC20(collateralToken).balanceOf(address(this))) revert InsufficientCollateral();

    IERC20(collateralToken).safeTransfer(msg.sender, collateralAmount);
    emit Redeemed(msg.sender, collateralToken, uspAmount, collateralAmount);
  }

  /// @notice Retrieves the oracle price for collateral and normalizes it to 18 decimals.
  /// @param primaryOracle The primary oracle address.
  /// @param primaryDecimals The decimals for the primary oracle.
  /// @param fallbackOracle The fallback oracle address.
  /// @param fallbackDecimals The decimals for the fallback oracle.
  /// @return price The normalized price (18 decimals).
  function getOraclePrice(
    address primaryOracle,
    uint8 primaryDecimals,
    address fallbackOracle,
    uint8 fallbackDecimals
  ) public view returns (uint256 price) {
    price = _getOracleData(primaryOracle, primaryDecimals);
    if (price > 0) {
      return price;
    }
    if (fallbackOracle != address(0)) {
      price = _getOracleData(fallbackOracle, fallbackDecimals);
      if (price > 0) {
        return price;
      }
    }
    revert InvalidOraclePrice();
  }

  /// @notice Retrieves the oracle price for collateral and normalizes it to 18 decimals.
  /// @param oracle The oracle address.
  /// @param feedDecimals The decimals for the oracle.
  /// @return price The normalized price (18 decimals).
  function _getOracleData(address oracle, uint8 feedDecimals) internal view returns (uint256) {
    (,int256 answer,,uint256 updatedAt,) = IPriceFeed(oracle).latestRoundData();
    if (updatedAt >= block.timestamp - 1 hours && answer > 0) {
      return uint256(answer) * 10 ** (18 - feedDecimals);
    }
    return 0;
  }

  /// @notice Emergency function for the owner to withdraw collateral tokens.
  /// @param token The collateral token address.
  /// @param amount The amount to withdraw.
  function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
    IERC20(token).safeTransfer(msg.sender, amount);
  }

  /// @notice Owner can pause the contract in emergencies.
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Owner can unpause the contract.
  function unpause() external onlyOwner {
    _unpause();
  }
}
