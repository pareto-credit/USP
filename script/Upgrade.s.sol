// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { Constants } from "../src/Constants.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Upgrades, Options } from "@openzeppelin/foundry-upgrades/Upgrades.sol";

contract DeployScript is Script, Constants {
  error Invalid();

  // TODO set address of the proxy contract
  address public constant PROXY = address(0);
  // contract name eg "ParetoDollar.sol"
  string public constant NEW_CONTRACT = "";
  string public constant OLD_CONTRACT = "";

  function run() public {
    vm.createSelectFork("mainnet");
    vm.startBroadcast();
    _upgrade(PROXY, OLD_CONTRACT, NEW_CONTRACT, "");
    vm.stopBroadcast();
  }

  function _upgrade(
    address proxy,
    string memory oldContract, 
    string memory newContract,
    // abi.encodeCall(MyContractV2.foo, ("arguments for foo"))
    // or "" for no initialize method
    bytes memory initializeCall
    ) public {
    if (proxy == address(0) || bytes(newContract).length == 0 || bytes(oldContract).length == 0) {
      revert Invalid();
    }
    // https://github.com/OpenZeppelin/openzeppelin-foundry-upgrades?tab=readme-ov-file#upgrade-a-proxy-or-beacon
    Options memory opts;
    opts.referenceContract = oldContract;
    // or 
    // opts.referenceBuildInfoDir = "/old-builds/build-info-v1";
    // opts.referenceContract = "build-info-v1:MyContract";

    // Validating the compatibility of the upgrade
    Upgrades.validateUpgrade(newContract, opts);

    console.log("Upgrading proxy at address:", proxy);

    Upgrades.upgradeProxy(proxy, newContract, initializeCall, opts);
    // Get the new implementation address after upgrade
    address implAddrV2 = Upgrades.getImplementationAddress(proxy);
    console.log('New implementation address:', implAddrV2);
  }
}
