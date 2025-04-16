// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { ParetoDollarQueue, IParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { Constants } from "../src/Constants.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Upgrades, Options } from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract DeployScript is Script, Constants {
  error Invalid();

  string public constant BUILD_INFO_DIR = "old-build-info/";

  // Optimism test contracts
  string public constant network = "optimism";
  address public constant PROXY = 0xe7783dc0f26370899a4D7063A7A843E035305e68;
  address public constant PROXY_QUEUE = 0x4C0E9ff6b196b52D894aE36bE5F2004e10dC1d43;
  address public constant PROXY_STAKING = 0xdb93Db15e1D65876eAAE19F01E50Ef506F935dF0;

  // Mainnet prod contracts
  // string public constant network = "mainnet";
  // address public constant PROXY = address(0);
  // address public constant PROXY_QUEUE = address(0);
  // address public constant PROXY_STAKING = address(0);

  function run() public {
    vm.createSelectFork(network);
    vm.startBroadcast();
    console.log('Upgrading in', network);
    _upgradeQueue();
    vm.stopBroadcast();
  }

  function _upgradeUSP() internal {
    _upgrade(PROXY, "ParetoDollar", "");
  }

  function _upgradeQueue() internal {
    _upgrade(PROXY_QUEUE, "ParetoDollarQueue", "");
  }

  function _upgradeSUSP() internal {
    _upgrade(PROXY_STAKING, "ParetoDollarStaking", "");
  }

  function _upgrade(
    address proxy,
    string memory oldContract,
    // abi.encodeCall(MyContractV2.foo, ("arguments for foo")) or "" for no initialize method
    bytes memory initializeCall
    ) public {
    if (proxy == address(0) || bytes(oldContract).length == 0) {
      revert Invalid();
    }

    console.log(string(abi.encodePacked("Upgrading ", oldContract, " at")), proxy);

    // https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades?tab=readme-ov-file#upgrade-a-proxy-or-beacon
    Options memory opts;
    opts.referenceBuildInfoDir = string(abi.encodePacked(BUILD_INFO_DIR, network));
    opts.referenceContract = string(abi.encodePacked(network, ":", oldContract));
    string memory contractFile = string(abi.encodePacked(oldContract, ".sol"));

    console.log('Reference contract      ', opts.referenceContract);
    console.log('Reference build info dir', opts.referenceBuildInfoDir);
    console.log('Contract file           ', contractFile);

    // Validating the compatibility of the upgrade
    Upgrades.validateUpgrade(contractFile, opts);
    // Upgrading the proxy
    Upgrades.upgradeProxy(proxy, contractFile, initializeCall, opts);
    // Log the new implementation address after upgrade
    console.log('New implementation address:', Upgrades.getImplementationAddress(proxy));

    console.log(string(abi.encodePacked('IMPORTANT: Move new build info from ', BUILD_INFO_DIR, ' to (replace old file) ', string(abi.encodePacked(BUILD_INFO_DIR, network)))));
  }
}
