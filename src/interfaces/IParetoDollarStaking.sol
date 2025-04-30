// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IParetoDollarStaking {
  function depositRewards(uint256 amount) external;
  function emergencyWithdraw(address token, uint256 amount) external;
}