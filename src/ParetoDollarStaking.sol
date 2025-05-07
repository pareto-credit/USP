// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import "./EmergencyUtils.sol";
import "./interfaces/IParetoDollarQueue.sol";

/* 

██████╗  █████╗ ██████╗ ███████╗████████╗ ██████╗     ███████╗██╗   ██╗███████╗██████╗ 
██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔═══██╗    ██╔════╝██║   ██║██╔════╝██╔══██╗
██████╔╝███████║██████╔╝█████╗     ██║   ██║   ██║    ███████╗██║   ██║███████╗██████╔╝
██╔═══╝ ██╔══██║██╔══██╗██╔══╝     ██║   ██║   ██║    ╚════██║██║   ██║╚════██║██╔═══╝ 
██║     ██║  ██║██║  ██║███████╗   ██║   ╚██████╔╝    ███████║╚██████╔╝███████║██║     
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝     ╚══════╝ ╚═════╝ ╚══════╝╚═╝     

*/ 

/// @title ParetoDollarStaking - A staking contract for ParetoDollar
/// @notice Users can stake ParetoDollar to earn yield from Pareto Credit Vaults. 
/// on deposits a staked version of the token is minted (sUSP) and can be redeemed for ParetoDollar after a cooldown period.
contract ParetoDollarStaking is ERC20Upgradeable, ERC4626Upgradeable, EmergencyUtils {
  using SafeERC20 for IERC20;

  //////////////
  /// Errors ///
  //////////////

  error FeeTooHigh();
  error NotAllowed();

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
  /// @notice ParetoDollarQueue contract address.
  address public queue;

  //////////////////////////
  /// Initialize methods ///
  //////////////////////////

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializer (replaces constructor for upgradeable contracts).
  /// @param _paretoDollar The address of the ParetoDollar contract.
  /// @param _admin The address of the admin.
  /// @param _pauser The address of the pauser.
  /// @param _queue The address of the ParetoDollarQueue contract.
  function initialize(
    address _paretoDollar,
    address _admin,
    address _pauser,
    address _queue
  ) public initializer {
    __ERC20_init(NAME, SYMBOL);
    __ERC4626_init(IERC20(_paretoDollar));
    __EmergencyUtils_init(_admin, _admin, _pauser);

    // set initial values
    rewardsVesting = 7 days;
    fee = FEE_100 / 20; // 5%
    feeReceiver = _admin;
    queue = _queue;
  }

  //////////////////////////
  /// Internal functions ///
  //////////////////////////

  /// @dev See {ERC4626Upgradeable-_deposit}.
  /// @dev if paused, deposits are not allowed
  function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
    _requireNotPaused();
    super._deposit(caller, receiver, assets, shares);
  }

  /// @dev See {ERC4626Upgradeable-_withdraw}.
  /// @dev if paused or not collateralized, withdraws are not allowed
  function _withdraw(address caller, address receiver, address _owner, uint256 assets, uint256 shares) internal override {
    _requireNotPaused();
    if (!IParetoDollarQueue(queue).isParetoDollarCollateralized()) {
      revert NotAllowed();
    }
    super._withdraw(caller, receiver, _owner, assets, shares);
  }

  /// @notice Get the amount of unvested rewards.
  /// @return _unvested The amount of unvested rewards.
  function _getUnvestedRewards() internal view returns (uint256 _unvested) {
    uint256 _rewardsVesting = rewardsVesting;
    uint256 _rewards = rewards;
    uint256 _timeSinceLastDeposit = block.timestamp - rewardsLastDeposit;
    // calculate unvested rewards
    if (_timeSinceLastDeposit < _rewardsVesting) {
      _unvested = _rewards - (_rewards * _timeSinceLastDeposit / _rewardsVesting);
    }
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @dev See {ERC4626Upgradeable-decimals}.
  function decimals() public view virtual override(ERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
    return 18;
  }

  /// @dev See {IERC4626-totalAssets}. Interest is vested over a period of time and is not immediately claimable.
  function totalAssets() public view override returns (uint256) {
    // return total assets minus unvested rewards
    uint256 _totAssets = super.totalAssets();
    uint256 _unvested = _getUnvestedRewards();
    if (_unvested > _totAssets) {
      return 0;
    }
    return _totAssets - _unvested;
  }

  ///////////////////////
  /// Admin functions ///
  ///////////////////////

  /// @notice Update the rewards vesting period.
  /// @param _rewardsVesting The new rewards vesting period.
  function updateRewardsVesting(uint256 _rewardsVesting) external {
    _checkOwner();
    uint256 _lastDeposit = rewardsLastDeposit;
    // check that old rewards are all vested and that the new vesting period won't re-vest rewards already released
    if (block.timestamp < _lastDeposit + rewardsVesting || block.timestamp < _lastDeposit + _rewardsVesting) {
      revert NotAllowed();
    }
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

  /// @notice Deposit rewards (ParetoDollars) to the contract.
  /// @dev Any unvested rewards will be added to the new rewards.
  /// @param amount The amount of rewards to deposit.
  function depositRewards(uint256 amount) external {
    // check that caller is queue contract
    if (msg.sender != queue) {
      revert NotAllowed();
    }
    IERC20 _asset = IERC20(asset());
    // transfer rewards from caller to this contract
    _asset.safeTransferFrom(msg.sender, address(this), amount);

    uint256 _fee = fee;
    uint256 _feeAmount;
    if (_fee > 0) {
      // transfer fees to fee receiver
      // if funds are donated to the contract with direct transfer, fees won't be accounted on the donated amount
      _feeAmount = amount * _fee / FEE_100;
      _asset.safeTransfer(feeReceiver, _feeAmount);
    }

    // update rewards data, add unvested rewards if any
    rewards = amount - _feeAmount + _getUnvestedRewards();
    rewardsLastDeposit = block.timestamp;

    emit RewardsDeposited(amount - _feeAmount);
  }

  /// @notice Emergency function for the owner/queue contract to withdraw collateral tokens.
  /// @param token The collateral token address.
  /// @param amount The amount to withdraw.
  function emergencyWithdraw(address token, uint256 amount) public override {
    if (msg.sender != owner() && msg.sender != queue) {
      revert NotAllowed();
    }

    // first apply loss to unvested rewards if any
    uint256 unvested = _getUnvestedRewards();
    rewards = amount < unvested ? unvested - amount : 0;

    IERC20(token).safeTransfer(msg.sender, amount);
  }

  /// @dev See {IERC4626-maxDeposit}. Returns 0 if paused.
  function maxDeposit(address _who) public view override returns (uint256) {
    return paused() ? 0 : super.maxDeposit(_who);
  }

  /// @dev See {IERC4626-maxMint}. Returns 0 if paused.
  function maxMint(address _who) public view override returns (uint256) {
    return paused() ? 0 : super.maxMint(_who);
  }

  /// @dev See {IERC4626-maxWithdraw}. Returns 0 if paused or system uncollateralized.
  function maxWithdraw(address _who) public view override returns (uint256) {
    return paused() || !IParetoDollarQueue(queue).isParetoDollarCollateralized() ? 0 : super.maxWithdraw(_who);
  }

  /// @dev See {IERC4626-maxRedeem}. Returns 0 if paused or system uncollateralized.
  function maxRedeem(address _who) public view override returns (uint256) {
    return paused() || !IParetoDollarQueue(queue).isParetoDollarCollateralized() ? 0 : balanceOf(_who);
  }
}