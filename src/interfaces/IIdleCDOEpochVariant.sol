// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface IIdleCDOEpochVariant {
  function token() external view returns (address);
  function AATranche() external view returns (address);
  function BBTranche() external view returns (address);
  function strategy() external view returns (address);
  function virtualPrice(address) external view returns (uint256);
  function bufferPeriod() external view returns (uint256);
  function epochEndDate() external view returns (uint256);
  function startEpoch() external;
  function stopEpoch(uint256, uint256) external;
  function fee() external view returns (uint256);
  function pendingWithdrawFees() external view returns (uint256);
  function expectedEpochInterest() external view returns (uint256);
  function isEpochRunning() external view returns (bool);
  function defaulted() external view returns (bool);
  function getContractValue() external view returns (uint256);
  function depositAA(uint256 amount) external returns (uint256);
  function requestWithdraw(uint256 tranches, address tranche) external;
  function owner() external view returns (address);
  function setKeyringParams(address _keyring, uint256 policy, bool) external;
  function oneToken() external view returns (uint256);
}