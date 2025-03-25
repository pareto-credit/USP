// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IParetoDollar.sol";
import "./interfaces/IParetoDollarQueue.sol";
import "./EmergencyUtils.sol";

/// @title ParetoDollarQueue - Contract to queue redemptions for ParetoDollar
contract ParetoDollarQueue is IParetoDollarQueue, ReentrancyGuardUpgradeable, EmergencyUtils {
  using SafeERC20 for IERC20Metadata;

  ///////////////////
  /// Error codes ///
  ///////////////////

  /// R0: Call reverted without revert data
  /// R1: Call reverted with invalid Error(string) data
  /// RC: Call reverted with custom error or panic

  /////////////////
  /// Constants ///
  /////////////////

  /// @notice role allowed to move funds out of the contract
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  /////////////////////////
  /// Storage variables ///
  /////////////////////////

  /// @notice ParetoDollar contract.
  IParetoDollar public par;
  /// @notice mapping of yield sources by address.
  mapping(address => YieldSource) public yieldSources;
  /// @notice mapping of withdraw requests per user per epoch
  mapping(address => mapping (uint256 => uint256)) public userWithdrawalsEpochs;
  /// @notice mapping of pending withdrawals (ParetoDollars) per epoch 
  mapping(uint256 => uint256) public epochPending;
  /// @notice total amount of ParetoDollar reserved for withdrawals and not yet redeemed
  uint256 public totReservedWithdrawals;
  /// @notice current epoch number used to group redeem requests
  uint256 public epochNumber;
  
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
  /// @param _par The address of the ParetoDollar contract.
  /// @param _managers The addresses of the managers.
  function initialize(
    address _admin,
    address _pauser,
    address _par,
    address[] memory _managers
  ) public initializer {
    __ReentrancyGuard_init();
    __EmergencyUtils_init(msg.sender, _admin, _pauser);
    par = IParetoDollar(_par);

    // manage roles
    for (uint256 i = 0; i < _managers.length; i++) {
      _grantRole(MANAGER_ROLE, _managers[i]);
    }

    // set epoch number to 1
    epochNumber = 1;
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @notice Get the total amount of collaterals available scaled to 18 decimals
  /// @return totCollateralBal The total amount of collaterals (18 decimals).
  function getTotCollateralBalanceScaled() public view returns (uint256 totCollateralBal) {
    address[] memory allCollaterals = par.getCollaterals();
    uint256 collateralsLen = allCollaterals.length;
    IERC20Metadata _collateral;
    // loop through the collaterals
    for (uint256 i = 0; i < collateralsLen; i++) {
      _collateral = IERC20Metadata(allCollaterals[i]);
      // get the balance of the collateral and scale it to 18 decimals
      totCollateralBal += _collateral.balanceOf(address(this)) * (10 ** (18 - _collateral.decimals()));
    }
  }

  /// @notice Get the yield source for a given address.
  /// @param _source The address of the yield source.
  /// @return The yield source.
  function getYieldSource(address _source) external view returns (YieldSource memory) {
    return yieldSources[_source];
  }

  //////////////////////////
  /// Internal functions ///
  //////////////////////////

  /// @notice Check if the caller is the ParetoDollar contract.
  function _onlyPar() internal view {
    if (msg.sender != address(par)) {
      revert NotAllowed();
    }
  }

  /// @notice get revert message from a failed call
  /// @param returnData The return data from the failed call.
  /// @return The revert message.
  function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
    // If there's no data, revert with a generic message
    if (returnData.length < 4) return "R0";

    // Peek at the first 4 bytes to check the error selector
    bytes4 selector;
    assembly {
      selector := mload(add(returnData, 32))
    }

    // "Error(string)" selector
    if (selector == 0x08c379a0) {
      // Only decodes the string if there's enough room
      if (returnData.length < 68) return "R1";
      // Skip the selector
      assembly {
        returnData := add(returnData, 4)
      }
      // Decode as (string)
      return abi.decode(returnData, (string));
    } 
    // Fallback for custom errors, panics, or anything else
    return "RC";
  }

  /// @notice Check if a method is allowed to be called on the yield source.
  /// @param _allowedMethods The list of allowed methods.
  /// @param _method The method to check.
  /// @return True if the method is allowed, false otherwise.
  function _isMethodAllowed(bytes4[] memory _allowedMethods, bytes4 _method) internal pure returns (bool) {
    uint256 _allowedMethodsLen = _allowedMethods.length;
    for (uint256 i = 0; i < _allowedMethodsLen; i++) {
      if (_allowedMethods[i] == _method) {
        return true;
      }
    }
    // needed to avoid warning during compilation
    return false;
  }

  ///////////////////////////
  /// Protected functions ///
  ///////////////////////////

  /// @notice allow the ParetoDollar contract to request collateral tokens from this contract
  /// @dev only the ParetoDollar contract can call this function
  /// @param _receiver The address of the receiver.
  /// @param _amount The amount of ParetoDollars to withdraw.
  function requestRedeem(address _receiver, uint256 _amount) external {
    // revert if the contract is paused
    _requireNotPaused();
    // revert if not called by the ParetoDollar contract
    _onlyPar();

    // updated user queued withdraw amount for the epoch
    uint256 _epoch = epochNumber;
    userWithdrawalsEpochs[_receiver][_epoch] += _amount;
    // update pending withdraw requests
    epochPending[_epoch] += _amount;
    // update total amount reserved for withdrawals
    totReservedWithdrawals += _amount;

    emit WithdrawRequested(_receiver, _amount, _epoch);
  }

  /// @notice allow the ParetoDollar contract to claim requested collateral tokens from this contract
  /// @dev only the ParetoDollar contract can call this function
  /// @param _receiver The address of the receiver.
  /// @param _epoch The epoch of the request.
  function claimRedeemRequest(address _receiver, uint256 _epoch) external returns (uint256) {
    // revert if the contract is paused
    _requireNotPaused();
    // revert if not called by the ParetoDollar contract
    _onlyPar();

    // check if withdraw requests were processed for the epoch
    // and if epoch is >= of the current epoch
    if (epochPending[_epoch] != 0 || _epoch > epochNumber - 1) {
      revert NotReady();
    }

    // amount is in USP
    uint256 amount = userWithdrawalsEpochs[_receiver][_epoch];
    if (amount == 0) {
      return 0;
    }
    // reset the user withdrawal amount
    userWithdrawalsEpochs[_receiver][_epoch] = 0;

    // transfer collaterals to the user (he can receive multiple collaterals)
    address[] memory allCollaterals = par.getCollaterals();
    uint256 collateralsLen = allCollaterals.length;
    uint256 _collateralAmount;
    uint256 _collateralDecimals;
    uint256 _amountLeft = amount;
    uint256 _collateralToTransfer;
    IERC20Metadata _collateralToken;
    // loop through the collaterals and transfer them to the user up to the USP amount requested
    // we treat collaterals (USDC, USDT) at 1:1 with USP
    for (uint256 i = 0; i < collateralsLen && _amountLeft > 0; i++) {
      _collateralToken = IERC20Metadata(allCollaterals[i]);
      // get collateral decimals
      _collateralDecimals = _collateralToken.decimals();
      // get the amount of collateral available and scale it to USP decimals (18)
      _collateralAmount = _collateralToken.balanceOf(address(this)) * (10 ** (18 - _collateralDecimals));
      if (_collateralAmount > 0) {
        // we check if the collateral amount is greater than the amount left to transfer
        _collateralToTransfer = _collateralAmount > _amountLeft ? _amountLeft : _collateralAmount;
        // update the amount left to transfer
        _amountLeft -= _collateralToTransfer;
        // transfer the collateral to the user
        // we scale back _collateralToTransfer from 18 decimals to the collateral decimals
        _collateralToken.safeTransfer(_receiver, _collateralToTransfer / (10 ** (18 - _collateralDecimals)));
      }
    }
    // check if the amount left to transfer is greater than 0
    if (_amountLeft > 0) {
      revert InsufficientBalance();
    }
    // update the total amount reserved for withdrawals
    totReservedWithdrawals -= amount;

    emit WithdrawRequestClaimed(_receiver, amount, _epoch);
    return amount;
  }

  /// @notice Redeem funds from yield sources.
  /// @dev only the manager can call this function. This should be used only when funds are received atomically
  /// so if yield source is a Credit Vault, this method should be called only when funds are ready to be claimed.
  /// For queueing Credit Vault withdraw requests, use the `callWhitelistedMethods` function directly.
  /// Funds redeemed will be first used to fullfill pending requests for the epoch if any.
  /// @param _sources Addresses of the yield sources.
  /// @param _methods Methods to call on yield sources.
  /// @param _args The arguments to pass to each the method.
  /// @param _epoch The epoch number.
  function redeemFunds(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args, uint256 _epoch) external {
    // revert if the contract is paused
    _requireNotPaused();
    // revert if the caller is not the manager
    _checkRole(MANAGER_ROLE);

    if (_epoch > epochNumber) {
      revert Invalid();
    }

    address[] memory _collaterals = par.getCollaterals();
    uint256 _collateralsLen = _collaterals.length;
    uint256[] memory _collateralBalBefore = new uint256[](_collateralsLen);
    // loop through the collaterals and get the balance before the call
    for (uint256 i = 0; i < _collateralsLen; i++) {
      _collateralBalBefore[i] = IERC20(_collaterals[i]).balanceOf(address(this));
    }

    // call the whitelisted methods on the yield sources
    callWhitelistedMethods(_sources, _methods, _args);

    uint256 totRedeemedScaled;
    IERC20Metadata _collateral;
    uint256[] memory _collateralGain = new uint256[](_collateralsLen);
    uint256 _epochPending = epochPending[_epoch];
    // loop through the collaterals and get the balance after the call
    for (uint256 i = 0; i < _collateralsLen; i++) {
      _collateral = IERC20Metadata(_collaterals[i]);
      _collateralGain[i] = _collateral.balanceOf(address(this)) - _collateralBalBefore[i];
      if (_collateralGain[i] > 0) {
        if (_epochPending > 0) {
          totRedeemedScaled += _collateralGain[i] * (10 ** (18 - _collateral.decimals()));
        }
        emit YieldSourceRedeem(_sources[i], _collaterals[i], _collateralGain[i]);
      }
    }

    // update pending withdrawals for the epoch
    if (totRedeemedScaled >= _epochPending) {
      // if there are pending requests and funds to fullfill all   
      // requests then we update epochPending
      if (_epochPending > 0) {
        epochPending[_epoch] = 0;
      }
    } else {
      epochPending[_epoch] -= totRedeemedScaled;
    }
  }

  /// @notice Increment the epoch number so to freeze the amount of pending requests.
  /// @dev only the manager can call this function, requests of the prev epoch should be processed
  function stopEpoch() external {
    // revert if the caller is not the manager
    _checkRole(MANAGER_ROLE);

    // check that request from previous epoch were processed
    uint256 _currEpoch = epochNumber;
    if (epochPending[_currEpoch - 1] > 0) {
      revert NotReady();
    }

    // update epoch number
    epochNumber += 1;

    emit NewEpoch(_currEpoch + 1);
  }

  // TODO

  // function depositYield() external {
  //   // revert if the caller is not the manager
  //   _checkRole(MANAGER_ROLE);

  //   // TODO supply is burned on redeem requests in ParetoDollar
  //   uint256 _uspSupply = par.totalSupply();
  //   // check value of vaultTokens
  //   // mint the difference??
  // }

  /// @notice Deposit funds into yield sources.
  /// @dev only the manager can call this function. NOTE: for Pareto Credit Vaults
  /// the deposit must be done during the buffer period without using the queue otherwise
  /// the depositAmount and maxCap will be incorrect. We check that the deposited amount is not 
  /// greater than the amount reserved for withdrawals of prev epochs.
  /// We use memory instead of calldata for first 2 parameters to avoid stack too deep error.
  /// @param _sources The list of vaults to deposit into.
  /// @param _methods The list of method signatures to call on the vaults.
  /// @param _args The arguments to pass to each the method.
  function depositFunds(
    address[] memory _sources,
    bytes4[] memory _methods,
    bytes[] calldata _args
  ) external {
    // revert if the contract is paused
    _requireNotPaused();
    // revert if the caller is not the manager
    _checkRole(MANAGER_ROLE);

    uint256 _vaultsLen = _sources.length;
    // check if the vaults and methods are the same length, check also if arguments have the same length
    if (_vaultsLen == 0 || _vaultsLen != _methods.length || _vaultsLen != _args.length) {
      revert Invalid();
    }
  
    YieldSource memory _yieldSource;
    bytes memory returnData;
    bytes4 selector;
    bool success;
    uint256 balPre;
    uint256 deposited;
    IERC20Metadata _token;
    // loop through the vaults and deposit funds
    for (uint256 i = 0; i < _vaultsLen; i++) {
      _yieldSource = yieldSources[_sources[i]];
      // revert if method is not allowed (will also revert if yield source is not defined)
      selector = _methods[i];
      if (!_isMethodAllowed(_yieldSource.allowedMethods, selector)) {
        revert NotAllowed();
      }
      _token = IERC20Metadata(_yieldSource.token);
      // deposit funds into the yield source
      balPre = _token.balanceOf(address(this));
      (success, returnData) = _sources[i].call(abi.encodePacked(selector, _args[i]));
      require(success, _getRevertMsg(returnData));

      // calculate deposited amount
      deposited = balPre - _token.balanceOf(address(this));
      _yieldSource.depositedAmount += deposited;
      // revert if the amount is greater than the max cap
      if (_yieldSource.depositedAmount > _yieldSource.maxCap) {
        revert MaxCap();
      }
      // save the depositedAmount in storage
      yieldSources[_sources[i]].depositedAmount = _yieldSource.depositedAmount;

      emit YieldSourceDeposit(_sources[i], _yieldSource.token, deposited);
    }

    // check if collaterals balances (scaled to 18 decimals) are greater than the totReservedWithdrawals
    if (getTotCollateralBalanceScaled() < totReservedWithdrawals) {
      revert InsufficientBalance();
    }

    // if collateral balances are greater than the totReservedWithdrawals
    // it means that all epochPending requests of the prev epoch can be fulfilled 
    // so we can reset the epochPending for the prev closed epoch
    epochPending[epochNumber - 1] = 0;
  }

  /// @notice Call multiple whitelisted methods on yield sources.
  /// @dev only the manager can call this function. This should not be used for deposits/redeems which have
  /// their own functions and account for balance changes
  /// @param _sources Addresses of the yield sources.
  /// @param _methods Methods to call on yield sources.
  /// @param _args The arguments to pass to each the method.
  function callWhitelistedMethods(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args) public {
    // revert if the contract is paused
    _requireNotPaused();
    // revert if the caller is not the manager
    _checkRole(MANAGER_ROLE);

    uint256 _sourcesLen = _sources.length;
    // revert if length of sources, methods and args are not the same
    if (_sourcesLen == 0 || _sourcesLen != _methods.length || _sourcesLen != _args.length) {
      revert Invalid();
    }

    bool success;
    bytes memory returnData;
    // loop through the sources and call the methods
    for (uint256 i = 0; i < _sourcesLen; i++) {
      // revert if the method is not allowed
      if (!_isMethodAllowed(yieldSources[_sources[i]].allowedMethods, _methods[i])) {
        revert NotAllowed();
      }
      // call the method on the yield source
      (success, returnData) = _sources[i].call(abi.encodePacked(_methods[i], _args[i]));
      require(success, _getRevertMsg(returnData));

      emit YieldSourceCall(_sources[i], _methods[i], _args[i]);
    }
  }

  /// @notice Add new yield source.
  /// @dev only the owner can call this function
  /// @param _source The address of the yield source.
  /// @param _token The address of the token used by the yield source.
  /// @param _vaultToken The address of the token used by the vault.
  /// @param _maxCap The maximum amount that can be deposited in the vault.
  /// @param allowedMethods The list of allowed methods to call on the yield source.
  function addYieldSource(
    address _source, 
    address _token, 
    address _vaultToken, 
    uint256 _maxCap, 
    bytes4[] calldata allowedMethods
  ) external {
    _checkOwner();
    // revert if the token is already in the yield sources
    if (yieldSources[_source].token != address(0)) {
      revert YieldSourceInvalid();
    }
    // add the token to the yield sources
    yieldSources[_source] = YieldSource(_token, _vaultToken, _maxCap, 0, allowedMethods);
    // approve the token for the yield source
    IERC20Metadata(_token).safeIncreaseAllowance(_source, type(uint256).max);
  }

  /// @notice Remove yield source.
  /// @dev only the owner can call this function. Yield source should be 
  /// removed only when everything is withdrawn from it.
  /// @param _source The address of the yield source.
  function removeYieldSource(address _source) external {
    _checkOwner();
    // revert if the token is not in the yield sources
    if (yieldSources[_source].token == address(0)) {
      revert YieldSourceInvalid();
    }
    IERC20Metadata _token = IERC20Metadata(yieldSources[_source].token);
    // remove allowance for the yield source
    _token.safeDecreaseAllowance(_source, _token.allowance(address(this), _source));
    // remove the yield source
    delete yieldSources[_source];
  }
}
