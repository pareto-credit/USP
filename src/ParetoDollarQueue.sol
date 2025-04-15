// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// OpenZeppelin upgradeable imports.
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IParetoDollar.sol";
import "./interfaces/IParetoDollarStaking.sol";
import "./interfaces/IParetoDollarQueue.sol";
import "./interfaces/IIdleCDOEpochVariant.sol";
import "./interfaces/IIdleCreditVault.sol";
import "./EmergencyUtils.sol";
import "./Constants.sol";

/* 

██████╗  █████╗ ██████╗ ███████╗████████╗ ██████╗      ██████╗ ██╗   ██╗███████╗██╗   ██╗███████╗
██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝██╔═══██╗    ██╔═══██╗██║   ██║██╔════╝██║   ██║██╔════╝
██████╔╝███████║██████╔╝█████╗     ██║   ██║   ██║    ██║   ██║██║   ██║█████╗  ██║   ██║█████╗  
██╔═══╝ ██╔══██║██╔══██╗██╔══╝     ██║   ██║   ██║    ██║▄▄ ██║██║   ██║██╔══╝  ██║   ██║██╔══╝  
██║     ██║  ██║██║  ██║███████╗   ██║   ╚██████╔╝    ╚██████╔╝╚██████╔╝███████╗╚██████╔╝███████╗
╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝   ╚═╝    ╚═════╝      ╚══▀▀═╝  ╚═════╝ ╚══════╝ ╚═════╝ ╚══════╝

*/

/// @title ParetoDollarQueue - Contract to queue redemptions for ParetoDollar
contract ParetoDollarQueue is IParetoDollarQueue, ReentrancyGuardUpgradeable, EmergencyUtils, Constants {
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
  /// @notice ParetoDollarStaking contract.
  IParetoDollarStaking public sPar;
  /// @notice mapping of yield sources by address.
  mapping(address => YieldSource) public yieldSources;
  /// @notice list of all yieldSources
  YieldSource[] public allYieldSources;
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
  /// @param _sPar The address of the ParetoDollarStaking contract.
  /// @param _managers The addresses of the managers.
  function initialize(
    address _admin,
    address _pauser,
    address _par,
    address _sPar,
    address[] memory _managers
  ) public initializer {
    __ReentrancyGuard_init();
    __EmergencyUtils_init(msg.sender, _admin, _pauser);
    par = IParetoDollar(_par);
    sPar = IParetoDollarStaking(_sPar);

    // manage roles
    for (uint256 i = 0; i < _managers.length; i++) {
      _grantRole(MANAGER_ROLE, _managers[i]);
    }

    // set epoch number to 1
    epochNumber = 1;
    // add allowance for ParetoDollar to ParetoDollarStaking
    IERC20Metadata(_par).safeIncreaseAllowance(_sPar, type(uint256).max);
    // add allowance for USDS to USDS-USDC PSM
    IERC20Metadata(USDS).safeIncreaseAllowance(USDS_USDC_PSM, type(uint256).max);
  }

  //////////////////////
  /// View functions ///
  //////////////////////

  /// @notice Get the yield source for a given address.
  /// @param _source The address of the yield source.
  /// @return The yield source.
  function getYieldSource(address _source) external view returns (YieldSource memory) {
    return yieldSources[_source];
  }

  /// @notice Get the list of all yield sources.
  /// @return The list of all yield sources.
  function getAllYieldSources() external view returns (YieldSource[] memory) {
    return allYieldSources;
  }

  /// @notice Get the total amount of collaterals available scaled to 18 decimals
  /// @return totCollateralBal The total amount of collaterals (18 decimals).
  function getUnlentBalanceScaled() public view returns (uint256 totCollateralBal) {
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

  /// @notice Get the total value of collaterals
  /// @return totCollaterals The total amount of collaterals scaled to 18 decimals.
  function getTotalCollateralsScaled() public view returns (uint256 totCollaterals) {
    // Get total amount of unlent balances in this contract
    address[] memory allCollaterals = par.getCollaterals();
    uint256 collateralsLen = allCollaterals.length;
    IERC20Metadata _collateral;
    // loop through all collaterals
    for (uint256 i = 0; i < collateralsLen; i++) {
      _collateral = IERC20Metadata(allCollaterals[i]);
      // get the balance of the collateral and scale it to 18 decimals
      totCollaterals += _collateral.balanceOf(address(this)) * (10 ** (18 - _collateral.decimals()));
    }

    uint256 sourcesLen = allYieldSources.length;
    // loop through all yield sources
    for (uint256 i = 0; i < sourcesLen; i++) {
      totCollaterals += getCollateralsYieldSourceScaled(allYieldSources[i].source);
    }
  }

  /// @notice Get the total value of collaterals in a yield source.
  /// @param _source The address of the yield source.
  /// @return assets The total value of collaterals in the yield source.
  function getCollateralsYieldSourceScaled(address _source) public view returns (uint256 assets) {
    YieldSource memory src = yieldSources[_source];
      if (src.vaultType == 1) {
      // Pareto Credit Vault
      assets = scaledNAVCreditVault(src.source, src.vaultToken, src.token);
    } else if (src.vaultType == 2) {
      // ERC4626 vault
      assets = scaledNAVERC4626(IERC4626(src.vaultToken));
    }
    // if vaultType is not one supported we skip it and return 0
  }

  //////////////////////////
  /// Internal functions ///
  //////////////////////////

  /// @notice Get the total value in this contract (scaled to 18 decimals) of a Pareto Credit Vault.
  /// @param yieldSource The address of the Pareto Credit Vault.
  /// @param vaultToken The address of the vault token (Tranche token).
  /// @param token The address of the underlying token.
  /// @return The total value of the Pareto Credit Vault in this contract.
  function scaledNAVCreditVault(address yieldSource, address vaultToken, IERC20Metadata token) internal view returns (uint256) {
    IIdleCDOEpochVariant cv = IIdleCDOEpochVariant(yieldSource);
    IIdleCreditVault strategy = IIdleCreditVault(cv.strategy());

    uint256 decimals = token.decimals();
    uint256 pending = strategy.withdrawsRequests(address(this)) * 10 ** (18 - decimals);
    uint256 instantPending = strategy.instantWithdrawsRequests(address(this)) * 10 ** (18 - decimals);
    // tranche balance in this contract (which have 18 decimals) * price (in underlying decimals) / 10 ** underlying decimals
    // we also need to add eventual pending withdraw requests (both normal and instant) as these requests burn tranche tokens
    return IERC20Metadata(vaultToken).balanceOf(address(this)) * cv.virtualPrice(cv.AATranche()) / (10 ** decimals) + pending + instantPending;
  }

  /// @notice Get the total value in this contract (scaled to 18 decimals) of an ERC4626 vault.
  /// @param vault The address of the ERC4626 vault token.
  /// @return The total value of the ERC4626 vault in this contract.
  function scaledNAVERC4626(IERC4626 vault) internal view returns (uint256) {
    // ERC4626 vault
    // convertToAssets returns value in underlying decimals so we scale it to 18 decimals
    return vault.convertToAssets(vault.balanceOf(address(this))) * 10 ** (18 - IERC20Metadata(vault.asset()).decimals());
  }

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

  /// @notice Call a method on a target address.
  /// @param _target The target address.
  /// @param _method The method to call.
  /// @param _args The arguments to pass to the method.
  /// @return The return data from the call.
  function _externalCall(address _target, bytes4 _method, bytes memory _args) internal returns (bytes memory) {
    // we restrict params so that destination address for PSM and 4626 are always set to this contract
    address _receiver = address(this);
    if (_method == BUY_GEM_SIG || _method == SELL_GEM_SIG) {
      // first param should be address(this) for interactions with USDS_USDC_PSM
      (_receiver,) = abi.decode(_args, (address, uint256));
    } else if (_method == DEPOSIT_4626_SIG) {
      // second param should be address(this) for deposits in 4626 vaults
      (,_receiver) = abi.decode(_args, (uint256, address));
    } else if (_method == WITHDRAW_4626_SIG || _method == REDEEM_4626_SIG) {
      // second param should be address(this) for redeem/withdraw from 4626 vaults
      (,_receiver,) = abi.decode(_args, (uint256, address, address));
    }
    if (_receiver != address(this)) {
      revert ParamNotAllowed();
    }
    
    (bool success, bytes memory returnData) = _target.call(abi.encodePacked(_method, _args));
    require(success, _getRevertMsg(returnData));
    return returnData;
  }

  /// @notice Check if a method is allowed to be called on the yield source and for a specific manager action.
  /// @param _method The method to check.
  /// @param _allowedMethods The list of allowed methods.
  /// @param funcType The type of function (0 = depositFunds, 1 = callWhitelistedMethods, 2 = redeemFunds).
  function _checkMethod(bytes4 _method, Method[] memory _allowedMethods, uint256 funcType) internal pure {
    uint256 _allowedMethodsLen = _allowedMethods.length;
    for (uint256 i = 0; i < _allowedMethodsLen; i++) {
      if (_allowedMethods[i].method == _method && _allowedMethods[i].methodType == funcType) {
        return;
      }
    }
    revert NotAllowed();
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

    return amount;
  }

  /// @notice Redeem funds from yield sources.
  /// @dev only the manager can call this function. This should be used only when funds are received atomically
  /// so if yield source is a Credit Vault, this method should be called only when funds are ready to be claimed.
  /// For queueing Credit Vault withdraw requests, use the `callWhitelistedMethods` function directly.
  /// Funds redeemed will be first used to fulfill pending requests for the epoch if any.
  /// @param _sources Addresses of the yield sources.
  /// @param _methods Methods to call on yield sources.
  /// @param _args The arguments to pass to each the method.
  /// @param _epoch The epoch number.
  function redeemFunds(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args, uint256 _epoch) external {
    // revert if the contract is paused
    _requireNotPaused();
    // revert if the caller is not the manager
    _checkRole(MANAGER_ROLE);

    uint256 vaultsLen = _sources.length;
    // check if the vaults and methods are the same length, 
    // check also if arguments have the same length and if epoch is valid
    if (vaultsLen == 0 || vaultsLen != _methods.length || vaultsLen != _args.length || _epoch > epochNumber) {
      revert Invalid();
    }
  
    YieldSource memory _yieldSource;
    uint256 balPre;
    uint256 redeemed;
    uint256 _epochPending = epochPending[_epoch];
    uint256 totRedeemedScaled;
    address source;

    // loop through the vaults and redeem funds
    for (uint256 i = 0; i < vaultsLen; i++) {
      source = _sources[i];
      _yieldSource = yieldSources[source];
      // revert if method is not allowed (will also revert if yield source is not defined)
      _checkMethod(_methods[i], _yieldSource.allowedMethods, 2);
      // redeem funds into the yield source
      balPre = _yieldSource.token.balanceOf(address(this));
      // do call on the yield source
      _externalCall(source, _methods[i], _args[i]);
      // calculate redeemed amount
      redeemed = _yieldSource.token.balanceOf(address(this)) - balPre;
      // update the depositedAmount in storage
      yieldSources[source].depositedAmount = getCollateralsYieldSourceScaled(source) / (10 ** (18 - _yieldSource.token.decimals()));
      if (redeemed > 0) {
        if (_epochPending > 0) {
          totRedeemedScaled += redeemed * (10 ** (18 - _yieldSource.token.decimals()));
        }
        emit YieldSourceRedeem(source, address(_yieldSource.token), redeemed);
      }
    }

    // update epochPending only for epochs already closed, not for the current epoch which is not yet closed
    if (_epoch != epochNumber) {
      // update pending withdrawals for the epoch
      if (totRedeemedScaled >= _epochPending) {
        // if there are pending requests and funds to fulfill all
        // requests then we update epochPending
        if (_epochPending > 0) {
          epochPending[_epoch] = 0;
        }
      } else {
        epochPending[_epoch] -= totRedeemedScaled;
      }
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

  /// @notice Deposit yield from vaults to ParetoDollarStaking
  /// @dev The function mints ParetoDollar and deposits them into ParetoDollarStaking.
  function depositYield() external {
    // revert if the caller is not the manager
    _checkRole(MANAGER_ROLE);

    // We first fetch total ParetoDollar supply and add the total amount of reserved withdrawals
    // which are ParetoDollars already burned but not yet claimed

    uint256 parSupply = IERC20Metadata(address(par)).totalSupply() + totReservedWithdrawals;
    // we calculate the total amount of collaterals available scaled to 18 decimals
    uint256 totCollaterals = getTotalCollateralsScaled();
    // calculate the gain
    uint256 gain = totCollaterals > parSupply ? totCollaterals - parSupply : 0;
    if (gain > 0) {
      // mint ParetoDollar to this contract equal to the gain
      par.mintForQueue(gain);
      // deposit ParetoDollar into the staking contract
      sPar.depositRewards(gain);
    }
  }

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
    if (_vaultsLen != _methods.length || _vaultsLen != _args.length) {
      revert Invalid();
    }
  
    YieldSource memory _yieldSource;
    uint256 balPre;
    uint256 deposited;
    uint256 totDeposited;
    // loop through the vaults and deposit funds
    for (uint256 i = 0; i < _vaultsLen; i++) {
      _yieldSource = yieldSources[_sources[i]];
      // revert if method is not allowed (will also revert if yield source is not defined)
      _checkMethod(_methods[i], _yieldSource.allowedMethods, 0);

      // deposit funds into the yield source
      balPre = _yieldSource.token.balanceOf(address(this));
      _externalCall(_sources[i], _methods[i], _args[i]);

      // calculate deposited amount
      deposited = balPre - _yieldSource.token.balanceOf(address(this));
      totDeposited = getCollateralsYieldSourceScaled(_sources[i]) / (10 ** (18 - _yieldSource.token.decimals()));
      // revert if the amount is greater than the max cap
      if (_yieldSource.maxCap > 0 && totDeposited > _yieldSource.maxCap) {
        revert MaxCap();
      }
      // save the depositedAmount in storage
      yieldSources[_sources[i]].depositedAmount = totDeposited;

      emit YieldSourceDeposit(_sources[i], address(_yieldSource.token), deposited);
    }

    uint256 _currEpoch = epochNumber;
    // check if collaterals balances (scaled to 18 decimals) are greater than
    // the totReservedWithdrawals minus the epochPending of the current epoch
    if (getUnlentBalanceScaled() < totReservedWithdrawals - epochPending[_currEpoch]) {
      revert InsufficientBalance();
    }

    // if collateral balances are greater than the totReservedWithdrawals - epochPending
    // for the curr epoch it means that all epochPending requests of the prev epoch can
    // be fulfilled so we can reset the epochPending for the prev closed epoch
    epochPending[_currEpoch - 1] = 0;
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

    // loop through the sources and call the methods
    for (uint256 i = 0; i < _sourcesLen; i++) {
      // revert if the method is not allowed
      _checkMethod(_methods[i], yieldSources[_sources[i]].allowedMethods, 1);
      // call the method on the yield source
      _externalCall(_sources[i], _methods[i], _args[i]);

      emit YieldSourceCall(_sources[i], _methods[i], _args[i]);
    }
  }

  /// @notice Add new yield source.
  /// @dev only the owner can call this function
  /// @param _source The address of the yield source.
  /// @param _token The address of the token used by the yield source.
  /// @param _vaultToken The address of the token used by the vault.
  /// @param _maxCap The maximum amount that can be deposited in the vault.
  /// @param _allowedMethods The list of allowed methods to call on the yield source.
  /// @param _vaultType The type of the vault (1 = Pareto Credit Vault, 2 = ERC4626).
  function addYieldSource(
    address _source, 
    address _token, 
    address _vaultToken, 
    uint256 _maxCap, 
    Method[] calldata _allowedMethods,
    uint8 _vaultType
  ) external {
    _checkOwner();
    // revert if the token is already in the yield sources
    if (address(yieldSources[_source].token) != address(0)) {
      revert YieldSourceInvalid();
    }
    if (_source == address(0) || _token == address(0) || _vaultToken == address(0) || _allowedMethods.length == 0) {
      revert Invalid();
    }
    YieldSource memory _yieldSource = YieldSource(IERC20Metadata(_token), _source, _vaultToken, _maxCap, 0, _allowedMethods, _vaultType);
    // add the token to the yield sources mapping
    yieldSources[_source] = _yieldSource;
    // add the token to the yield sources list
    allYieldSources.push(_yieldSource);
    // approve the token for the yield source
    IERC20Metadata(_token).safeIncreaseAllowance(_source, type(uint256).max);

    emit YieldSourceAdded(_source, _token);
  }

  /// @notice Remove yield source.
  /// @dev only the owner can call this function. Yield source should be 
  /// removed only when everything is withdrawn from it. This is checked
  /// using `depositedAmount` in the yield source struct, if the yield
  /// source is not used with `depositFunds`/`redeemFunds` then this should
  /// be manually checked
  /// @param _source The address of the yield source.
  function removeYieldSource(address _source) external {
    _checkOwner();

    YieldSource memory _ys = yieldSources[_source];
    // revert if the token is not in the yield sources
    if (address(_ys.token) == address(0)) {
      revert YieldSourceInvalid();
    }
    // revert if the yield source is not empty, no need to unscale the value
    if (getCollateralsYieldSourceScaled(_source) > 0) {
      revert YieldSourceNotEmpty();
    }
    // remove allowance for the yield source
    _ys.token.safeDecreaseAllowance(_source, _ys.token.allowance(address(this), _source));
    // remove the yield source from mapping
    delete yieldSources[_source];
    // remove the source from the list of all yield sources
    // order is not preserved but it's not important (last el can be reallocated)
    YieldSource[] memory _sources = allYieldSources;
    uint256 sourcesLen = _sources.length;
    for (uint256 i = 0; i < sourcesLen; i++) {
      if (address(_sources[i].token) == address(_ys.token)) {
        allYieldSources[i] = _sources[sourcesLen - 1];
        allYieldSources.pop();
        break;
      }
    }
    emit YieldSourceRemoved(_source);
  }
}
