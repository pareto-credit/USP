// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

/// @title ParetoDollarStaking - A staking contract for ParetoDollar
/// @notice Users can stake ParetoDollar to earn yield from Pareto Credit Vaults. 
/// on deposits a staked version of the token is minted (sUSP) and can be redeemed for ParetoDollar after a cooldown period.
contract ParetoDollarStaking is ERC20Upgradeable, ERC4626Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  /////////////////
  /// Constants ///
  /////////////////

  /// @notice Token symbol.
  string public constant SYMBOL = "sUSP";
  /// @notice Token name.
  string public constant NAME = "Pareto staked USP";

  /////////////////////////
  /// Storage variables ///
  /////////////////////////


  //////////////////////////
  /// Initialize methods ///
  //////////////////////////

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializer (replaces constructor for upgradeable contracts).
  function initialize(address _paretoDollar) public initializer {
    __ERC20_init(NAME, SYMBOL);
    __ERC4626_init(IERC20(_paretoDollar));
    __Ownable_init(msg.sender);
    __Pausable_init();
    __ReentrancyGuard_init();
  }

  ////////////////////////
  /// Public functions ///
  ////////////////////////

  
  //////////////////////
  /// View functions ///
  //////////////////////

  /// @dev See {ERC4626Upgradeable-decimals}.
  function decimals() public view virtual override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
    return 18;
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

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