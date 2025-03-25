// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface IIdleCreditVault {
  function withdrawsRequests(address) external view returns (uint256);
  function manager() external view returns (address);
  function borrower() external view returns (address);
  function pendingWithdraws() external view returns (uint256);
  function pendingInstantWithdraws() external view returns (uint256);
  function unscaledApr() external view returns (uint256);
  function epochNumber() external view returns (uint256);
  function lastWithdrawRequest(address) external view returns (uint256);
}