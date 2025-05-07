// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPSM {
  function tin() external view returns (uint256);
  function tout() external view returns (uint256);
}