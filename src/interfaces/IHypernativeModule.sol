// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
interface IHypernativeModule {
  enum ContractType {
    JUNIOR_OR_SENIOR,
    TRANCH
  }

  struct ProtectedContract {
    address contractAddress;
    ContractType contractType;
  }

  function updateProtectedContracts(ProtectedContract[] memory _protectedContracts) external;
  function isContractProtected(address _address) external view returns (bool);
}