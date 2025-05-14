// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { Upgrades } from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { ParetoDollarQueue, IParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { Constants } from "../src/Constants.sol";
import { IHypernativeModule } from "../src/interfaces/IHypernativeModule.sol";
import { IIdleCDOEpochVariant } from "../src/interfaces/IIdleCDOEpochVariant.sol";
import { Safe } from "safe-utils/Safe.sol";

contract ManagerSpells is Script, Constants {
  using Safe for *;

  Safe.Client safe;
  string public constant network = "mainnet";
  ParetoDollar public par = ParetoDollar(0x97cCC1C046d067ab945d3CF3CC6920D3b1E54c88);
  ParetoDollarStaking public sPar = ParetoDollarStaking(0x271C616157e69A43B4977412A64183Cf110Edf16);
  ParetoDollarQueue public queue = ParetoDollarQueue(0xA7780086ab732C110E9E71950B9Fb3cb2ea50D89); 
  bool public IS_EOA = true;

  function run() public {
    vm.createSelectFork(network);
    console.log('Using network: ', network);
    console.log('Using multisig: ', !IS_EOA);
    
    safe.initialize(TL_MULTISIG);

    vm.startBroadcast();
    // Choose the proper spell here:

    // PSM spells
    // sellUSDCPSM(0); // amount in USDC
    // buyUSDCPSM(0); // amount in USDC

    // sUSD spells
    // depositToSUSD(0); // amount in USDS
    // redeemFromSUSD(0, 0); // amount in sUSDS, epoch number

    // Bastion spells
    // depositToCV(BAS_USDC_CV, 0); // amount in USDC
    // requestRedeemCV(BAS_USDC_CV, 0); // amount in AA tranches
    // claimRequestCV(BAS_USDC_CV, false); // isInstant

    // Fasara spells
    // depositToCV(FAS_USDC_CV, 0); // amount in USDC
    // requestRedeemCV(FAS_USDC_CV, 0); // amount in AA tranches
    // claimRequestCV(FAS_USDC_CV, false); // isInstant

    // Utility spells
    // stopEpoch();
    // accountGainsLosses();

    vm.stopBroadcast();
  }

  /// @param amount Amount of USDS to deposit. If 0, will deposit all USDS in the queue.
  function depositToSUSD(uint256 amount) public {
    if (amount == 0) {
      amount = IERC20Metadata(USDS).balanceOf(address(queue));
    }

    address[] memory sources = new address[](1);
    sources[0] = SUSDS;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = DEPOSIT_4626_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(amount, address(queue));
    
    console.log('Depositing:', amount / 1e18, 'USDS to sUSDS vault');

    _depositFunds(sources, methods, args);
  }

  /// @param amount Amount of sUSDS to redeem. If 0, will redeem all sUSDS in the queue.
  function redeemFromSUSD(uint256 amount, uint256 _epoch) public {
    if (amount == 0) {
      amount = IERC20Metadata(SUSDS).balanceOf(address(queue));
    }
    if (_epoch == 0) {
      _epoch = queue.epochNumber();
    }

    address[] memory sources = new address[](1);
    sources[0] = SUSDS;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = REDEEM_4626_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(amount, address(queue), address(queue));

    console.log('Redeeming:', amount / 1e18, 'sUSDS from sUSDS vault');
    console.log('Epoch number:', _epoch);
    
    _redeemFunds(sources, methods, args, _epoch);
  }

  /// @param amount Amount of USDC to swap for USDS. If 0, will swap all USDC in the queue.
  function sellUSDCPSM(uint256 amount) public {
    if (amount == 0) {
      amount = IERC20Metadata(USDC).balanceOf(address(queue));
    }

    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = USDS_USDC_PSM;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = SELL_GEM_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(address(queue), amount);
    
    console.log('Selling:', amount / 1e6, 'USDC for USDS');

    _callWhitelistedMethods(sources, methods, args);
  }

  /// @param amount Amount of USDC to buy. If 0, will swap all USDS in the queue.
  function buyUSDCPSM(uint256 amount) public {
    if (amount == 0) {
      amount = IERC20Metadata(USDS).balanceOf(address(queue));
    }

    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = USDS_USDC_PSM;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = BUY_GEM_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(address(queue), amount / 1e12);

    console.log('Buying:', amount / 1e18, 'USDC for USDS');

    _callWhitelistedMethods(sources, methods, args);
  }

  /// @param source Address of the credit vault to deposit to.
  /// @param amount Amount of collateral to deposit. If 0, will deposit all collateral in the queue.
  function depositToCV(address source, uint256 amount) public {
    IERC20Metadata token = IERC20Metadata(IIdleCDOEpochVariant(source).token());
    uint256 decimals = token.decimals();
    string memory symbol = token.symbol();
    
    if (amount == 0) {
      amount = token.balanceOf(address(queue));
    }

    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = DEPOSIT_AA_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(amount);
    console.log('Depositing:', amount / 10 ** (decimals), symbol, 'to CV vault');
    console.log('CV:', source);

    _depositFunds(sources, methods, args);
  }

  /// @param source Address of the credit vault to redeem from.
  /// @param trancheAmount Amount of AA tranches to redeem. If 0, will request to redeem all AA tranches in the queue.
  function requestRedeemCV(address source, uint256 trancheAmount) public {
    IIdleCDOEpochVariant cv = IIdleCDOEpochVariant(source);
    address aaTranche = cv.AATranche();

    if (trancheAmount == 0) {
      trancheAmount = IERC20Metadata(aaTranche).balanceOf(address(queue));
    }

    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = WITHDRAW_AA_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(trancheAmount, aaTranche);

    console.log('Requesting redeem:', trancheAmount / 1e18, 'AA tranches from CV vault');
    console.log('CV:', source);

    _callWhitelistedMethods(sources, methods, args);
  }

  /// @param source Address of the credit vault to claim from.
  /// @param isInstant Whether to claim the instant redeem request or not.
  function claimRequestCV(address source, bool isInstant) public {
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = isInstant ? CLAIM_INSTANT_REQ_SIG : CLAIM_REQ_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode();

    console.log('Claiming redeem request from CV vault, isInstant:', isInstant);
    console.log('CV:', source);

    _callWhitelistedMethods(sources, methods, args);
  }

  function stopEpoch() public {
    if (IS_EOA) {
      queue.stopEpoch();
    } else {
      _multisigTx(
        abi.encodeCall(IParetoDollarQueue.stopEpoch, ())
      );
    }
  }

  function accountGainsLosses() public {
    if (IS_EOA) {
      queue.accountGainsLosses();
    } else {
      _multisigTx(
        abi.encodeCall(IParetoDollarQueue.accountGainsLosses, ())
      );
    }
  }

  function _multisigTx(bytes memory data) internal {
    safe.proposeTransaction(address(queue), data, DEPLOYER, "m/44'/60'/0'/0/0");
  }
  
  function _depositFunds(address[] memory sources, bytes4[] memory methods, bytes[] memory args) internal {
    if (IS_EOA) {
      queue.depositFunds(sources, methods, args);
    } else {
      _multisigTx(
        abi.encodeCall(IParetoDollarQueue.depositFunds, (sources, methods, args))
      );
    }
  }

  function _redeemFunds(address[] memory sources, bytes4[] memory methods, bytes[] memory args, uint256 _epoch) internal {
    if (IS_EOA) {
      queue.redeemFunds(sources, methods, args, _epoch);
    } else {
      _multisigTx(
        abi.encodeCall(IParetoDollarQueue.redeemFunds, (sources, methods, args, _epoch))
      );
    }
  }

  function _callWhitelistedMethods(address[] memory sources, bytes4[] memory methods, bytes[] memory args) internal {
    if (IS_EOA) {
      queue.callWhitelistedMethods(sources, methods, args);
    } else {
      _multisigTx(
        abi.encodeCall(IParetoDollarQueue.callWhitelistedMethods, (sources, methods, args))
      );
    }
  }
}
