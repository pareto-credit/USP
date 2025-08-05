// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @dev this contract is not used by other contracts but it only contains references
/// of contracts deployed.
contract Addresses {
  // MAINNET
  address public constant TIMELOCK = 0xDa86e15d0Cda3A05Db930b248d7a2f775e575A44;
  address public constant USP = 0x97cCC1C046d067ab945d3CF3CC6920D3b1E54c88;
  address public constant USP_ADMIN = 0x05B230e3E35f45E8579062eB91c34e51Da082a32;
  address public constant QUEUE = 0xA7780086ab732C110E9E71950B9Fb3cb2ea50D89;
  address public constant QUEUE_ADMIN = 0x8ce03DB1b4a52B42dd188DB5ddf8C6e23FF99526;
  address public constant SUSP = 0x271C616157e69A43B4977412A64183Cf110Edf16;
  address public constant SUSP_ADMIN = 0x5570A71dBF28859DA00d24e3544274BdDc81e989;
  address public constant BALANCER_ARB = 0xD94736DCfA7A020a962994A1eE77382BC1613326;

  // morpho sUSP/USDC market and oracle
  address public constant MORPHO_SUSP_USDC_ORACLE = 0x373F6155264c3424Cd0D1cA2c7C29FF1998F19d0;
  bytes32 public constant MORPHO_SUSP_USDC_MARKET = 0xb80caf498db6593f2b93fdac04acd9ce35d90977936597b4bc0913eb6b5837d3;
}