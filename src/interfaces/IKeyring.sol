// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface IKeyring {
  function checkCredential(uint256 policyId, address entity) external view returns (bool);
  function setWhitelistStatus(address entity, bool status) external;
}