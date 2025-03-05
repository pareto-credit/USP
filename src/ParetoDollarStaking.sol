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

  //////////////
  /// Errors ///
  //////////////

  error FeeTooHigh();

  //////////////
  /// Events ///
  //////////////

  event RewardsDeposited(uint256 amount);

  /////////////////
  /// Constants ///
  /////////////////

  /// @notice Token symbol.
  string public constant SYMBOL = "sUSP";
  /// @notice Token name.
  string public constant NAME = "Pareto staked USP";
  /// @notice reference value for 100% fee
  uint256 public constant FEE_100 = 100_000; // 100% fee
  /// @notice max fee
  uint256 public constant MAX_FEE = 20_000; // max fee is 20%

  /////////////////////////
  /// Storage variables ///
  /////////////////////////

  /// @notice Rewards vesting period in seconds.
  uint256 public rewardsVesting;
  /// @notice Amount of rewards to release.
  uint256 public rewards;
  /// @notice Timestamp when rewards were last deposited.
  uint256 public rewardsLastDeposit;
  /// @notice fee on interest earned
  uint256 public fee;
  /// @notice address to receive fees
  address public feeReceiver;

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

    rewardsVesting = 7 days;
    fee = FEE_100 / 20; // 5%
    feeReceiver = msg.sender;
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

  /// @dev See {IERC4626-totalAssets}. Interest is vested over a period of time and is not immediately claimable.
  function totalAssets() public view override returns (uint256) {
    uint256 _rewardsVesting = rewardsVesting;
    uint256 _rewards = rewards;
    uint256 _timeSinceLastDeposit = block.timestamp - rewardsLastDeposit;
    // calculate unvested rewards
    uint256 unvestedRewards;
    if (_timeSinceLastDeposit < _rewardsVesting) {
      unvestedRewards = _rewards - (_rewards * _timeSinceLastDeposit / _rewardsVesting);
    }
    // return total assets minus unvested rewards
    return IERC20(asset()).balanceOf(address(this)) - unvestedRewards;
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

  /// @notice Update the rewards vesting period.
  /// @param _rewardsVesting The new rewards vesting period.
  function updateRewardsVesting(uint256 _rewardsVesting) external {
    _checkOwner();
    rewardsVesting = _rewardsVesting;
  }

  /// @notice Update the fee parameters.
  /// @param _fee The new fee.
  /// @param _feeReceiver The new fee receiver.
  function updateFeeParams(uint256 _fee, address _feeReceiver) external {
    _checkOwner();
    if (_fee > MAX_FEE) {
      revert FeeTooHigh();
    }
    fee = _fee;
    feeReceiver = _feeReceiver;
  }

  /// @notice Deposit rewards to the contract.
  /// @dev if method is called when prev rewards are not yet vested, old rewards become vested
  /// @param amount The amount of rewards to deposit.
  function depositRewards(uint256 amount) external {
    _checkOwner();
    // transfer rewards from caller to this contract
    IERC20(asset()).safeTransferFrom(msg.sender, address(this), amount);

    uint256 _fee = fee;
    uint256 _feeAmount;
    if (_fee > 0) {
      // transfer fees to fee receiver
      _feeAmount = amount * _fee / FEE_100;
      IERC20(asset()).safeTransfer(feeReceiver, _feeAmount); // use _feeAmount here
    }

    // update rewards data
    rewards = amount - _feeAmount;
    rewardsLastDeposit = block.timestamp;

    emit RewardsDeposited(amount - _feeAmount);
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