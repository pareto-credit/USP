// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

interface IParetoDollarQueue {
    //////////////
  /// Errors ///
  //////////////

  error Invalid();
  error NotAllowed();
  error NotReady();
  error YieldSourceInvalid();
  error YieldSourceNotEmpty();
  error InsufficientBalance();
  error MaxCap();
  error ParamNotAllowed();

  //////////////
  /// Events ///
  //////////////

  event YieldSourceDeposit(address indexed source, address indexed token, uint256 amount);
  event YieldSourceRedeem(address indexed source, address indexed token, uint256 amount);
  event YieldSourceCall(address indexed source, bytes4 indexed method, bytes args);
  event YieldSourceAdded(address indexed source, address indexed token);
  event YieldSourceRemoved(address indexed source);
  event NewEpoch(uint256 indexed epoch);

  /// @notice Allowed methods structure.
  struct Method {
    bytes4 method; // method signature
    uint8 methodType; // 0 = depositFunds, 1 = callWhitelistedMethods, 2 = redeemFunds
  }

  /// @notice Yield source structure.
  struct YieldSource {
    IERC20Metadata token;  // underlying token used by the vault
    address source; // address of the yield source
    address vaultToken; // token used by the vault
    uint256 maxCap; // maximum amount that can be deposited in the vault (interest is not included)
    uint256 depositedAmount; // amount deposited in the vault (interest is not included)
    Method[] allowedMethods; // allowed methods to call on the vault
    uint8 vaultType; // type of the vault (1 = Pareto Credit Vault, 2 = ERC4626)
  }

  function requestRedeem(address _receiver, uint256 _amount) external;
  function claimRedeemRequest(address _receiver, uint256 _epoch) external returns (uint256);
  function getUnlentBalanceScaled() external view returns (uint256 totUnlentBalance);
  function getTotalCollateralsScaled() external view returns (uint256 totCollateralBal);
  function redeemFunds(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args, uint256 _epoch) external;
  function depositFunds(address[] memory _sources, bytes4[] memory _methods, bytes[] calldata _args) external; 
  function callWhitelistedMethods(address[] calldata _sources, bytes4[] calldata _methods, bytes[] calldata _args) external;
  function addYieldSource(
    address _source, 
    address _token, 
    address _vaultToken, 
    uint256 _maxCap, 
    Method[] calldata allowedMethods,
    uint8 _vaultType
  ) external;
  function removeYieldSource(address _source) external;
}