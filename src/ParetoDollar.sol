// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/IKeyring.sol";
import "./interfaces/IParetoDollar.sol";
import "./EmergencyUtils.sol";
import "./ParetoDollarQueue.sol";

/* 

██████╗  █████╗ ██████╗ ███████╗████████╗ ██████╗     ██╗   ██╗███████╗██████╗ 
██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔═══██╗    ██║   ██║██╔════╝██╔══██╗
██████╔╝███████║██████╔╝█████╗     ██║   ██║   ██║    ██║   ██║███████╗██████╔╝
██╔═══╝ ██╔══██║██╔══██╗██╔══╝     ██║   ██║   ██║    ██║   ██║╚════██║██╔═══╝ 
██║     ██║  ██║██║  ██║███████╗   ██║   ╚██████╔╝    ╚██████╔╝███████║██║     
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝      ╚═════╝ ╚══════╝╚═╝     

*/ 

/// @title ParetoDollar - A synthetic dollar minted 1:1 against approved collateral tokens
/// @notice Users can mint ParetoDollar (USP) by depositing supported collateral tokens and redeem USP for collateral tokens.
/// Minting enforces a minimum collateral price threshold (0.99 USD normalized to 18 decimals) using primary and fallback oracles,
/// while redemption does not enforce this check.
/// Collateral will be deposited in Pareto Credit Vaults to earn yield.
contract ParetoDollar is IParetoDollar, ERC20Upgradeable, ReentrancyGuardUpgradeable, EmergencyUtils {
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
  /// @notice Collateral token list.
  address[] public collaterals;
  /// @notice Keyring wallet checker address
  address public keyring;
  /// @notice keyring policyId
  uint256 public keyringPolicyId;
  /// @notice Address of the queue contract for redemptions and deployments.
  ParetoDollarQueue public queue;

  //////////////////////////
  /// Initialize methods ///
  //////////////////////////

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializer (replaces constructor for upgradeable contracts).
  /// @param _admin The admin address.
  /// @param _pauser The pauser address.
  /// @param _queue The address of the queue contract.
  function initialize(
    address _admin,
    address _pauser,
    address _queue
  ) public initializer {
    __ERC20_init(NAME, SYMBOL);
    __ReentrancyGuard_init();
    __EmergencyUtils_init(msg.sender, _admin, _pauser);

    queue = ParetoDollarQueue(_queue);
  }

  ////////////////////////
  /// Public functions ///
  ////////////////////////

  /// @notice Mint USP by depositing an allowed collateral token.
  /// @dev Only mints if the collateral's normalized price is at least 0.99 USD.
  /// @param collateralToken The collateral token address.
  /// @param amount The amount of collateral tokens to deposit.
  /// @return scaledAmount The amount of USP minted (in 18 decimals).
  function mint(address collateralToken, uint256 amount) external nonReentrant returns (uint256 scaledAmount) {
    // check if the contract is paused and wallet is allowed
    _checkAllowed(msg.sender);
    // check if the collateral token is allowed
    CollateralInfo memory info = collateralInfo[collateralToken];
    if (!info.allowed) {
      revert CollateralNotAllowed();
    }
    // check if collateral price is above the minimum threshold
    if (getOraclePrice(collateralToken) < MIN_PRICE) {
      revert CollateralPriceBelowThreshold();      
    }

    // mint ParetoDollars
    scaledAmount = amount * 10 ** (18 - info.tokenDecimals);
    _mint(msg.sender, scaledAmount);

    // transfer the collateral to the queue contract
    IERC20(collateralToken).safeTransferFrom(msg.sender, address(queue), amount);
    emit Minted(msg.sender, collateralToken, amount, scaledAmount);
  }

  /// @notice Request redemption of USP for collateral tokens.
  /// @dev This function is used to request a redemption of USP for collateral tokens.
  /// @param _uspAmount The amount of USP to redeem (18 decimals).
  function requestRedeem(uint256 _uspAmount) external nonReentrant {
    // check if the contract is paused and wallet is allowed
    _checkAllowed(msg.sender);
    // burn USP from user
    _burn(msg.sender, _uspAmount);
    // make the request for redemption
    queue.requestRedeem(msg.sender, _uspAmount);
    emit RedeemRequested(msg.sender, queue.epochNumber(), _uspAmount);
  }

  /// @notice Claim collateral tokens.
  /// @param epoch The epoch number of the request.
  function claimRedeemRequest(uint256 epoch) external nonReentrant returns(uint256 amountRequested) {
    // check if the contract is paused and wallet is allowed
    _checkAllowed(msg.sender);
    // claim the request for collateral
    amountRequested = queue.claimRedeemRequest(msg.sender, epoch);
    emit Redeemed(msg.sender, epoch, amountRequested);
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @notice Check if the contract is paused and wallet is allowed.
  /// @param _user The user address.
  function _checkAllowed(address _user) internal view {
    // check if the contract is paused
    _requireNotPaused();
    // check if msg.sender is allowed 
    if (!isWalletAllowed(_user)) {
      revert NotAllowed();
    }
  }

  /// @notice Retrieves the oracle price for collateral and normalizes it to 18 decimals.
  /// @param token The collateral token address.
  /// @return price The normalized price (18 decimals).
  function getOraclePrice(address token) public view returns (uint256 price) {
    CollateralInfo memory info = collateralInfo[token];
    if (!info.allowed) {
      revert CollateralNotAllowed();
    }
    // Fetch latest round data from the oracle
    (,int256 answer,,uint256 updatedAt,) = IPriceFeed(info.priceFeed).latestRoundData();
    // if validity period is 0, it means that we accept any price > 0
    // othwerwise, we check if the price is updated within the validity period
    if (answer > 0 && (info.validityPeriod == 0 || (updatedAt >= block.timestamp - info.validityPeriod))) {
      // scale the value to 18 decimals
      return uint256(answer) * 10 ** (18 - info.priceFeedDecimals);
    }
    revert InvalidOraclePrice();
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

  /// @notice Retrieve the list of collateral tokens.
  /// @return The list of collateral token addresses.
  function getCollaterals() external view returns (address[] memory) {
    return collaterals;
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

  /// @notice Burn USP from owner. This is used when there is a loss from one of the borrower
  /// and USP are withdrawed by the owner from the sUSP contract. In this way sUSP holders will absorb the loss
  /// @param _uspAmount amount of USP to burn.
  function emergencyBurn(uint256 _uspAmount) external {
    _checkOwner();

    _burn(msg.sender, _uspAmount);
  }

  /// @notice Add new collateral
  /// @dev IMPORTANT: be sure that priceFeed has no min/max answer
  /// @dev This method can be used also to update collateral info by passing the same token address
  /// @param token The collateral token address.
  /// @param tokenDecimals The decimals for the collateral token.
  /// @param priceFeed The primary oracle address.
  /// @param priceFeedDecimals The decimals for the primary oracle.
  /// @param validityPeriod The validity period for the oracle price (in seconds).
  function addCollateral(
    address token,
    uint8 tokenDecimals,
    address priceFeed,
    uint8 priceFeedDecimals,
    uint256 validityPeriod
  ) external {
    _checkOwner();

    if (token == address(0) || priceFeed == address(0)) revert InvalidData();
    // check if the token is already added
    bool isOverwriting = collateralInfo[token].allowed;
    collateralInfo[token] = CollateralInfo({
      allowed: true,
      priceFeed: priceFeed,
      tokenDecimals: tokenDecimals,
      priceFeedDecimals: priceFeedDecimals,
      validityPeriod: validityPeriod
    });
    // add the token to the list of collaterals
    if (!isOverwriting) {
      collaterals.push(token);
    }
    emit CollateralAdded(token, priceFeed, tokenDecimals, priceFeedDecimals, validityPeriod);
  }

  /// @notice Remove collateral
  /// @dev Collateral should be removed only if there are no yield sources using it anymore
  /// and all redeem requests for that collateral have been fulfilled.
  /// @param token The collateral token address to remove.
  function removeCollateral(address token) external {
    _checkOwner();

    if (token == address(0)) revert InvalidData();
    delete collateralInfo[token];
    // remove the token from the list of collaterals
    // order is not preserved but it's not important (last el can be reallocated)
    address[] memory _collaterals = collaterals;
    uint256 collateralsLen = _collaterals.length;
    for (uint256 i = 0; i < collateralsLen; i++) {
      if (_collaterals[i] == token) {
        collaterals[i] = _collaterals[collateralsLen - 1];
        collaterals.pop();
        break;
      }
    }
    emit CollateralRemoved(token);
  }

  /// @notice Mint ParetoDollar for the queue contract.
  /// @param _amount The amount of USP to mint.
  function mintForQueue(uint256 _amount) external {
    if (msg.sender != address(queue)) {
      revert NotAllowed();
    }
    // mint ParetoDollar to the queue
    _mint(address(queue), _amount);
  }

  /// @notice update keyring address
  /// @param _keyring address of the keyring contract
  /// @param _keyringPolicyId policyId to check for wallet
  function setKeyringParams(address _keyring, uint256 _keyringPolicyId) external {
    _checkOwner();

    keyring = _keyring;
    keyringPolicyId = _keyringPolicyId;
  }
}
