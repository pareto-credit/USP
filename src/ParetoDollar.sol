// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IKeyring.sol";
import "./interfaces/IParetoDollar.sol";

/// @title ParetoDollar - A synthetic dollar minted 1:1 against approved collateral tokens
/// @notice Users can mint ParetoDollar (USP) by depositing supported collateral tokens and redeem USP for collateral tokens.
/// Minting enforces a minimum collateral price threshold (0.99 USD normalized to 18 decimals) using primary and fallback oracles,
/// while redemption does not enforce this check.
/// Collateral will be deposited in Pareto Credit Vaults to earn yield.
contract ParetoDollar is IParetoDollar, ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  /////////////////
  /// Constants ///
  /////////////////

  /// @notice Minimum acceptable price (normalized to 18 decimals): 0.99 USD.
  uint256 public constant MIN_PRICE = 99 * 1e16; // 0.99 * 1e18
  /// @notice Token symbol.
  string public constant SYMBOL = "USP";
  /// @notice Token name.
  string public constant NAME = "Pareto synthetic dollar USP";

  /////////////////////////
  /// Storage variables ///
  /////////////////////////

  /// @notice Mapping from collateral token address to its info.
  mapping(address => CollateralInfo) public collateralInfo;

  /// @notice Keyring wallet checker address
  address public keyring;
  /// @notice keyring policyId
  uint256 public keyringPolicyId;

  //////////////////////////
  /// Initialize methods ///
  //////////////////////////

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializer (replaces constructor for upgradeable contracts).
  function initialize() public initializer {
    __ERC20_init(NAME, SYMBOL);
    __Ownable_init(msg.sender);
    __Pausable_init();
    __ReentrancyGuard_init();
  }

  ////////////////////////
  /// Public functions ///
  ////////////////////////

  /// @notice Mint USP by depositing an allowed collateral token.
  /// @param collateralToken The collateral token address.
  /// @param amount The amount of collateral tokens to deposit.
  /// @dev Only mints if the collateral's normalized price is at least 0.99 USD.
  function mint(address collateralToken, uint256 amount) external whenNotPaused nonReentrant {
    if (!isWalletAllowed(msg.sender)) {
      revert NotAllowed();
    }

    CollateralInfo memory info = collateralInfo[collateralToken];
    if (!info.allowed) {
      revert CollateralNotAllowed();
    }
    if (getOraclePrice(collateralToken) < MIN_PRICE) {
      revert CollateralPriceBelowThreshold();      
    }

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
    if (!isWalletAllowed(msg.sender)) {
      revert NotAllowed();
    }
    CollateralInfo memory info = collateralInfo[collateralToken];
    if (!info.allowed) revert CollateralNotAllowed();

    _burn(msg.sender, uspAmount);
    uint256 collateralAmount = uspAmount / (10 ** (18 - info.tokenDecimals));
    if (collateralAmount > IERC20(collateralToken).balanceOf(address(this))) revert InsufficientCollateral();

    IERC20(collateralToken).safeTransfer(msg.sender, collateralAmount);
    emit Redeemed(msg.sender, collateralToken, uspAmount, collateralAmount);
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @notice Retrieves the oracle price for collateral and normalizes it to 18 decimals.
  /// @param token The collateral token address.
  /// @return price The normalized price (18 decimals).
  function getOraclePrice(address token) public view returns (uint256 price) {
    CollateralInfo memory info = collateralInfo[token];
    if (!info.allowed) {
      revert CollateralNotAllowed();
    }
    price = _getOraclePrice(
      info.priceFeed,
      info.priceFeedDecimals,
      info.fallbackPriceFeed,
      info.fallbackPriceFeedDecimals
    );
  }

  /// @notice Retrieves the oracle price for collateral and normalizes it to 18 decimals.
  /// @param primaryOracle The primary oracle address.
  /// @param primaryDecimals The decimals for the primary oracle.
  /// @param fallbackOracle The fallback oracle address.
  /// @param fallbackDecimals The decimals for the fallback oracle.
  /// @return price The normalized price (18 decimals).
  function _getOraclePrice(
    address primaryOracle,
    uint8 primaryDecimals,
    address fallbackOracle,
    uint8 fallbackDecimals
  ) internal view returns (uint256 price) {
    price = _getScaledOracleAnswer(primaryOracle, primaryDecimals);
    if (price > 0) {
      return price;
    }
    if (fallbackOracle != address(0)) {
      price = _getScaledOracleAnswer(fallbackOracle, fallbackDecimals);
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
  function _getScaledOracleAnswer(address oracle, uint8 feedDecimals) internal view returns (uint256) {
    (,int256 answer,,uint256 updatedAt,) = IPriceFeed(oracle).latestRoundData();
    if (updatedAt >= block.timestamp - 6 hours && answer > 0) {
      return uint256(answer) * 10 ** (18 - feedDecimals);
    }
    return 0;
  }

  /// @notice Check if wallet is allowed to interact with the contract
  /// @param _user User address
  /// @return true if wallet is allowed or keyring address is not set
  function isWalletAllowed(address _user) public view returns (bool) {
    address _keyring = keyring;
    return _keyring == address(0) || IKeyring(_keyring).checkCredential(keyringPolicyId, _user);
  }

  /// @notice Get collateral info for a specific token.
  /// @param token The collateral token address.
  /// @return info The collateral info.
  function getCollateralInfo(address token) external view returns (CollateralInfo memory) {
    return collateralInfo[token];
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

  /// @notice Owner can add a new collateral token.
  /// @param token The collateral token address.
  /// @param tokenDecimals The decimals for the collateral token.
  /// @param priceFeed The primary oracle address.
  /// @param priceFeedDecimals The decimals for the primary oracle.
  /// @param fallbackPriceFeed The fallback oracle address (can be address(0) if not used).
  /// @param fallbackPriceFeedDecimals The decimals for the fallback oracle.
  function addCollateral(
    address token,
    uint8 tokenDecimals,
    address priceFeed,
    uint8 priceFeedDecimals,
    address fallbackPriceFeed,
    uint8 fallbackPriceFeedDecimals
  ) external {
    _checkOwner();

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
  function removeCollateral(address token) external {
    _checkOwner();

    if (token == address(0)) revert InvalidData();
    collateralInfo[token].allowed = false;
    emit CollateralRemoved(token);
  }

  /// @notice update keyring address
  /// @param _keyring address of the keyring contract
  /// @param _keyringPolicyId policyId to check for wallet
  function setKeyringParams(address _keyring, uint256 _keyringPolicyId) external {
    _checkOwner();

    keyring = _keyring;
    keyringPolicyId = _keyringPolicyId;
  }

  /// @notice Emergency function for the owner to withdraw collateral tokens.
  /// @param token The collateral token address.
  /// @param amount The amount to withdraw.
  function emergencyWithdraw(address token, uint256 amount) external {
    _checkOwner();

    IERC20(token).safeTransfer(msg.sender, amount);
  }

  /// @notice Owner can pause the contract in emergencies.
  function pause() external {
    _checkOwner();
    _pause();
  }

  /// @notice Owner can unpause the contract.
  function unpause() external {
    _checkOwner();
    _unpause();
  }
}
