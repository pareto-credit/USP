// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IParetoDollarQueue {
    //////////////
  /// Errors ///
  //////////////

  error Invalid();
  error NotAllowed();
  error NotReady();
  error YieldSourceInvalid();
  error InsufficientBalance();
  error MaxCap();

  //////////////
  /// Events ///
  //////////////

  event YieldSourceDeposit(address indexed source, address indexed token, uint256 amount);
  event YieldSourceRedeem(address indexed source, address indexed token, uint256 amount);
  event YieldSourceCall(address indexed source, bytes4 indexed method, bytes args);
  event NewEpoch(uint256 indexed epoch);

  /// @notice Yield source structure.
  struct YieldSource {
    address token;  // underlying token used by the vault
    address vaultToken; // token used by the vault
    uint256 maxCap; // maximum amount that can be deposited in the vault (interest is not included)
    uint256 depositedAmount; // amount deposited in the vault (interest is not included)
    bytes4[] allowedMethods; // allowed methods to call on the vault
  }

  function requestRedeem(address _receiver, uint256 _amount) external;
  function claimRedeemRequest(address _receiver, uint256 _epoch) external returns (uint256);
  function getTotCollateralBalanceScaled() external view returns (uint256 totCollateralBal);
  function redeemFunds(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args, uint256 _epoch) external;
  function depositFunds(address[] memory _sources, bytes4[] memory _methods, bytes[] calldata _args) external; 
  function callWhitelistedMethods(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args) external;
  function addYieldSource(
    address _source, 
    address _token, 
    address _vaultToken, 
    uint256 _maxCap, 
    bytes4[] calldata allowedMethods
  ) external;
  function removeYieldSource(address _source) external;
}