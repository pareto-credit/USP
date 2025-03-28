// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { Test, stdStorage, StdStorage } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { IParetoDollar } from "../src/interfaces/IParetoDollar.sol";
import { IParetoDollarQueue } from "../src/interfaces/IParetoDollarQueue.sol";
import { IPriceFeed } from "../src/interfaces/IPriceFeed.sol";
import { IIdleCDOEpochVariant } from "../src/interfaces/IIdleCDOEpochVariant.sol";
import { IIdleCreditVault } from "../src/interfaces/IIdleCreditVault.sol";
import { IKeyring } from "../src/interfaces/IKeyring.sol";
import { DeployScript, Constants } from "../script/Deploy.s.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC4626 } from  "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract TestParetoDollarQueue is Test, DeployScript {
  using SafeERC20 for IERC20Metadata;
  using stdStorage for StdStorage;

  ParetoDollar par;
  ParetoDollarStaking sPar;
  ParetoDollarQueue queue;

  function setUp() public virtual {
    // In this block FAS_USDC_CV is in netting period, this is important
    vm.createSelectFork("mainnet", 22068555);

    vm.startPrank(DEPLOYER);
    (par, sPar, queue) = _deploy(false);
    vm.stopPrank();

    // whitelist the queue contract to be able to interact with credit vaults
    vm.prank(TL_MULTISIG);
    IKeyring(KEYRING_WHITELIST).setWhitelistStatus(address(queue), true);

    vm.prank(par.owner());
    par.setOracleValidityPeriod(0);

    skip(100);
  }

  function testInitialize() external view {
    assertEq(queue.owner(), TL_MULTISIG, 'owner is wrong');
    assertEq(address(queue.par()), address(par), 'ParetoDollar address is wrong');
    assertEq(address(queue.sPar()), address(sPar), 'ParetoDollarStaking address is wrong');
    assertEq(IERC20Metadata(address(par)).allowance(address(queue), address(sPar)), type(uint256).max, 'allowance for staking contract is wrong');
    assertEq(IERC20Metadata(USDC).allowance(address(queue), address(USDS_USDC_PSM)), type(uint256).max, 'allowance for USDC for PSM contract is wrong');
    assertEq(IERC20Metadata(USDS).allowance(address(queue), address(USDS_USDC_PSM)), type(uint256).max, 'allowance for USDS for PSM contract is wrong');

    assertEq(queue.hasRole(queue.DEFAULT_ADMIN_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have DEFAULT_ADMIN_ROLE');
    assertEq(queue.hasRole(queue.PAUSER_ROLE(), HYPERNATIVE_PAUSER), true, 'HYPERNATIVE_PAUSER should have PAUSER_ROLE');
    assertEq(queue.hasRole(queue.PAUSER_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have PAUSER_ROLE');
    assertEq(queue.hasRole(queue.MANAGER_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have MANAGER_ROLE');
    assertEq(queue.isPausable(), true, 'the contract should be pausable');
    assertEq(queue.epochNumber(), 1, 'epoch number should be 0');
    assertEq(queue.getAllYieldSources().length, 3, 'yield source length is wrong');
    assertEq(queue.getAllYieldSources()[0].source, FAS_USDC_CV, 'yield source is wrong');
    assertEq(queue.getAllYieldSources()[1].source, SUSDS, 'yield source 2 is wrong');
    assertEq(queue.getAllYieldSources()[2].source, USDS_USDC_PSM, 'yield source 3 is wrong');

    ParetoDollarQueue.YieldSource memory source = queue.getYieldSource(FAS_USDC_CV);
    assertEq(address(source.token), USDC, 'token is wrong');
    assertEq(source.source, FAS_USDC_CV, 'source is wrong');
    assertEq(source.vaultToken, AA_FAS_USDC_CV, 'vault token is wrong');
    assertEq(source.maxCap, 100_000_000 * 1e6, 'vault max cap is wrong');
    assertEq(source.depositedAmount, 0, 'vault deposited amount is wrong');
    assertEq(source.vaultType, 1, 'vault type deposited amount is wrong');
    assertEq(source.allowedMethods.length, 4, 'vault allowed methods is wrong');
    assertEq(source.allowedMethods[0], DEPOSIT_AA_SIG, 'first allowed method is wrong');
    assertEq(source.allowedMethods[1], WITHDRAW_AA_SIG, 'second allowed method is wrong');
    assertEq(source.allowedMethods[2], CLAIM_REQ_SIG, 'third allowed method is wrong');
    assertEq(source.allowedMethods[3], CLAIM_INSTANT_REQ_SIG, 'fourth allowed method is wrong');

    ParetoDollarQueue.YieldSource memory sourceUSDS = queue.getYieldSource(SUSDS);
    assertEq(address(sourceUSDS.token), USDS, 'token for USDS source is wrong');
    assertEq(sourceUSDS.source, SUSDS, 'source for USDS source is wrong');
    assertEq(sourceUSDS.vaultToken, SUSDS, 'vault token for USDS source is wrong');
    assertEq(sourceUSDS.maxCap, 100_000_000 * 1e18, 'vault max cap for USDS source is wrong');
    assertEq(sourceUSDS.depositedAmount, 0, 'vault deposited amount for USDS source is wrong');
    assertEq(sourceUSDS.vaultType, 2, 'vault type for USDS source deposited amount is wrong');
    assertEq(sourceUSDS.allowedMethods.length, 3, 'vault allowed methods for USDS source is wrong');
    assertEq(sourceUSDS.allowedMethods[0], DEPOSIT_4626_SIG, 'first allowed method for USDS source is wrong');
    assertEq(sourceUSDS.allowedMethods[1], WITHDRAW_4626_SIG, 'second allowed method for USDS source is wrong');
    assertEq(sourceUSDS.allowedMethods[2], REDEEM_4626_SIG, 'third allowed method for USDS source is wrong');

    ParetoDollarQueue.YieldSource memory sourcePSM = queue.getYieldSource(USDS_USDC_PSM);
    assertEq(address(sourcePSM.token), USDC, 'token for USDS PSM source is wrong');
    assertEq(sourcePSM.source, USDS_USDC_PSM, 'source for USDS PSM source is wrong');
    assertEq(sourcePSM.vaultToken, USDS, 'vault token for USDS PSM source is wrong');
    assertEq(sourcePSM.maxCap, 0, 'vault max cap for USDS PSM source is wrong');
    assertEq(sourcePSM.depositedAmount, 0, 'vault deposited amount for USDS PSM source is wrong');
    assertEq(sourcePSM.vaultType, 0, 'vault type for USDS PSM source deposited amount is wrong');
    assertEq(sourcePSM.allowedMethods.length, 2, 'vault allowed methods for USDS PSM source is wrong');
    assertEq(sourcePSM.allowedMethods[0], BUY_GEM_SIG, 'first allowed method for USDS PSM source is wrong');
    assertEq(sourcePSM.allowedMethods[1], SELL_GEM_SIG, 'second allowed method for USDS PSM source is wrong');
  }

  function testEmergencyWithdraw() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    queue.emergencyWithdraw(address(1), 1);

    deal(USDC, address(queue), 100);

    uint256 balPre = IERC20Metadata(USDC).balanceOf(queue.owner());

    vm.startPrank(queue.owner());
    queue.emergencyWithdraw(USDC, 100);
    uint256 balPost = IERC20Metadata(USDC).balanceOf(queue.owner());
    assertEq(balPost, balPre + 100, 'owner balance should increase by 100');
    vm.stopPrank();
  }

  function testPause() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), par.PAUSER_ROLE()));
    queue.pause();

    vm.startPrank(queue.owner());
    queue.pause();
    assertEq(queue.paused(), true, 'The contract should be paused');
    vm.stopPrank();

    // when paused no mints or redeems can be made
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    queue.requestRedeem(address(this), 1e6);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    queue.claimRedeemRequest(address(this), 1e6);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    queue.redeemFunds(new address[](0), new bytes4[](0), new bytes[](0), 1);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    queue.depositFunds(new address[](0), new bytes4[](0), new bytes[](0));
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    queue.callWhitelistedMethods(new address[](0), new bytes4[](0), new bytes[](0));
    vm.stopPrank();
  }

  function testUnpause() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    queue.unpause();

    vm.startPrank(queue.owner());
    queue.pause();
    queue.unpause();

    assertEq(queue.paused(), false, 'The contract should not be paused');
    vm.stopPrank();
  }

  function testRoles() external {
    bytes32 manager = queue.MANAGER_ROLE();
    bytes32 pauser = queue.PAUSER_ROLE();
    bytes32 defaultAdmin = queue.DEFAULT_ADMIN_ROLE();

    bytes memory defaultError = abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdmin);

    // if non admin tries to grant role, it reverts
    vm.expectRevert(defaultError);
    queue.grantRole(manager, address(this));
    vm.expectRevert(defaultError);
    queue.grantRole(pauser, address(this));
    vm.expectRevert(defaultError);
    queue.grantRole(defaultAdmin, address(this));

    // if non admin tries to removke role, it reverts
    vm.expectRevert(defaultError);
    queue.revokeRole(manager, address(this));
    vm.expectRevert(defaultError);
    queue.revokeRole(pauser, address(this));
    vm.expectRevert(defaultError);
    queue.revokeRole(defaultAdmin, address(this));

    // admin can grant roles
    address admin = TL_MULTISIG;
    vm.startPrank(admin);
    queue.grantRole(manager, address(this));
    queue.grantRole(pauser, address(this));
    queue.grantRole(defaultAdmin, address(this));
    assertEq(queue.hasRole(manager, address(this)), true, 'address(this) should have MANAGER_ROLE');
    assertEq(queue.hasRole(pauser, address(this)), true, 'address(this) should have PAUSER_ROLE');
    assertEq(queue.hasRole(defaultAdmin, address(this)), true, 'address(this) should have DEFAULT_ADMIN_ROLE');
    vm.stopPrank();

    // admin can revoke roles
    vm.startPrank(admin);
    queue.revokeRole(manager, address(this));
    queue.revokeRole(pauser, address(this));
    queue.revokeRole(defaultAdmin, address(this));
    assertEq(queue.hasRole(manager, address(this)), false, 'address(this) should not have MANAGER_ROLE');
    assertEq(queue.hasRole(pauser, address(this)), false, 'address(this) should not have PAUSER_ROLE');
    assertEq(queue.hasRole(defaultAdmin, address(this)), false, 'address(this) should not have DEFAULT_ADMIN_ROLE');
    vm.stopPrank();
  }

  function testAddYieldSource() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    queue.addYieldSource(address(1), USDC, AA_FAS_USDC_CV, 0, new bytes4[](0), 0);

    vm.startPrank(queue.owner());
    // revert for yield source already present
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.YieldSourceInvalid.selector));
    queue.addYieldSource(FAS_USDC_CV, USDC, AA_FAS_USDC_CV, 10, new bytes4[](0), 0);

    IIdleCDOEpochVariant cdo = IIdleCDOEpochVariant(0xdd4D030A4337CE492B55bc5169F6A9568242C0Bc);
    bytes4[] memory allowedMethods = new bytes4[](4);
    allowedMethods[0] = DEPOSIT_AA_SIG;
    allowedMethods[1] = WITHDRAW_AA_SIG;
    allowedMethods[2] = CLAIM_REQ_SIG;
    allowedMethods[3] = CLAIM_INSTANT_REQ_SIG;
    vm.expectEmit(true, true, true, true);
    emit IParetoDollarQueue.YieldSourceAdded(address(cdo), USDC);
    queue.addYieldSource(address(cdo), cdo.token(), cdo.AATranche(), 10, allowedMethods, 1);
    ParetoDollarQueue.YieldSource memory source = queue.getYieldSource(address(cdo));
    assertEq(address(source.token), USDC, 'vault token is wrong');
    assertEq(source.maxCap, 10, 'vault max cap is wrong');
    assertEq(source.depositedAmount, 0, 'vault deposited amount is wrong');
    assertEq(source.vaultToken, cdo.AATranche(), 'vault token is wrong');
    assertEq(source.vaultType, 1, 'vault typer is wrong');
    assertEq(source.allowedMethods.length, 4, 'vault allowed methods is wrong');
    assertEq(source.allowedMethods[0], DEPOSIT_AA_SIG, 'first allowed method is wrong');
    assertEq(source.allowedMethods[1], WITHDRAW_AA_SIG, 'second allowed method is wrong');
    assertEq(source.allowedMethods[2], CLAIM_REQ_SIG, 'third allowed method is wrong');
    assertEq(source.allowedMethods[3], CLAIM_INSTANT_REQ_SIG, 'fourth allowed method is wrong');

    // one source was added at deployment and another one in this test
    assertEq(queue.getAllYieldSources().length, 4, 'there should be 4 yield sources');
    assertEq(queue.getAllYieldSources()[3].source, address(cdo), 'yield source is wrong');
    // check allowance
    assertEq(IERC20Metadata(USDC).allowance(address(queue), address(cdo)), type(uint256).max, 'allowance is wrong');
    vm.stopPrank();
  }

  function testRemoveYieldSource() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    queue.removeYieldSource(address(1));

    vm.startPrank(queue.owner());
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.YieldSourceInvalid.selector));
    queue.removeYieldSource(address(1));
  
    vm.expectEmit(true, true, true,true);
    emit IParetoDollarQueue.YieldSourceRemoved(FAS_USDC_CV);
    queue.removeYieldSource(FAS_USDC_CV);
    ParetoDollarQueue.YieldSource memory source = queue.getYieldSource(FAS_USDC_CV);
    assertEq(address(source.token), address(0), 'vault token should be removed');
    assertEq(source.maxCap, 0, 'vault max cap should be removed');
    assertEq(source.depositedAmount, 0, 'vault deposited amount is wrong');
    assertEq(source.vaultToken, address(0), 'vault token is wrong');
    assertEq(source.vaultType, 0, 'vault type is wrong');
    assertEq(source.allowedMethods.length, 0, 'vault allowed methods should be removed');
    assertEq(queue.getAllYieldSources().length, 2, 'there should be 2 yield sources');
    // we removed the first yield source so the last one (USDS_USDC_PSM) will replace it 
    assertEq(queue.getAllYieldSources()[0].source, USDS_USDC_PSM, 'first yield source should be USDS_USDC_PSM');
    assertEq(queue.getAllYieldSources()[1].source, SUSDS, 'second yield source should be SUSDS');
    // check allowance
    assertEq(IERC20Metadata(USDC).allowance(address(queue), FAS_USDC_CV), 0, 'allowance should be removed');
    vm.stopPrank();
  }

  function testGetUnlentBalanceScaled() external {
    uint256 totCollateral = queue.getUnlentBalanceScaled();
    assertEq(totCollateral, 0, 'total collateral should be 0');

    // deposit via ParetoDollar
    _mintUSP(address(this), USDC, 1e6);
    // the result is scaled to 18 decimals
    assertEq(queue.getUnlentBalanceScaled(), 1e18, 'total collateral should be updated after deposit');
    // deposit via ParetoDollar
    // test with a different collateral
    _mintUSP(address(this), USDT, 2e6);
    // the result is scaled to 18 decimals
    assertEq(queue.getUnlentBalanceScaled(), 3e18, 'total collateral should be updated after second deposit');

    // buy USDS
    _sellUSDCPSM(1e6);
    assertEq(queue.getUnlentBalanceScaled(), 3e18, 'total collateral should be updated after USDS buy');
  }

  function testDepositFundsSingleVault() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), queue.MANAGER_ROLE()));
    queue.depositFunds(new address[](0), new bytes4[](0), new bytes[](0));

    // deposit 100 USDC in the vault
    uint256 amount = 100e6;
    _mintUSP(address(this), USDC, amount);

    vm.startPrank(TL_MULTISIG);
    // call with parameters with different length should revert
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.depositFunds(new address[](0), new bytes4[](1), new bytes[](0));
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.depositFunds(new address[](1), new bytes4[](0), new bytes[](1));
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.depositFunds(new address[](1), new bytes4[](1), new bytes[](0));

    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = FAS_USDC_CV;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = bytes4(keccak256(bytes("evilDeposit(uint256)")));
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(amount);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotAllowed.selector));
    queue.depositFunds(sources, methods, args);

    // set the correct deposit method
    uint256 balPre = IERC20Metadata(USDC).balanceOf(address(queue));
    methods[0] = DEPOSIT_AA_SIG;
    args[0] = abi.encode(amount);

    vm.expectEmit(true, true, true,true);
    emit IParetoDollarQueue.YieldSourceDeposit(FAS_USDC_CV, USDC, amount);
    queue.depositFunds(sources, methods, args);

    ParetoDollarQueue.YieldSource memory source = queue.getYieldSource(FAS_USDC_CV);
    assertEq(source.depositedAmount, amount, 'vault deposited amount is wrong');
    assertGt(IERC20Metadata(source.vaultToken).balanceOf(address(queue)), 0, 'vault balance should be greater than 0');
    assertEq(IERC20Metadata(USDC).balanceOf(address(queue)), balPre - amount, 'queue token balance should be updated');
    vm.stopPrank();

    // deposit 100M USDC in the vault to check that MaxCap error is triggered
    amount = source.maxCap;
    _mintUSP(address(1), USDC, amount);
    args[0] = abi.encode(amount);

    vm.startPrank(TL_MULTISIG);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.MaxCap.selector));
    queue.depositFunds(sources, methods, args);
    vm.stopPrank();

    // manually set total reserved withdrawals to 1000 USDC
    uint256 reserved = 1000e6;
    stdstore
      .target(address(queue))
      .sig(queue.totReservedWithdrawals.selector)
      .checked_write(reserved * 10 ** 12); // should be scaled to 18 decimals

    // check that after deposit there are at least 1000 USDC in the vault
    // we are depositing 99_999_001 USDC and leaving 999USDC in the contract
    args[0] = abi.encode(amount - (reserved - 1)); 
    vm.startPrank(TL_MULTISIG);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.InsufficientBalance.selector));
    queue.depositFunds(sources, methods, args);
    vm.stopPrank();
  }

  function testRequestRedeem() external {
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotAllowed.selector));
    queue.requestRedeem(address(this), 1e6);

    uint256 epochNumber = queue.epochNumber();
    // deposit 100 USDC in the vault
    uint256 amount = 100e6;
    uint256 scaledAmount = amount * 10 ** 12; // should be scaled to 18 decimals
    _mintUSP(address(this), USDC, amount);

    vm.startPrank(address(this));
    // redeem requests should be done via ParetoDollar
    par.requestRedeem(scaledAmount / 2);

    assertEq(queue.userWithdrawalsEpochs(address(this), epochNumber), scaledAmount / 2, 'user withdrawal epoch should be updated');
    assertEq(queue.epochPending(epochNumber), scaledAmount / 2, 'epoch pending should be updated');
    assertEq(queue.totReservedWithdrawals(), scaledAmount / 2, 'total reserved withdrawals should be updated');

    // redeem requests another redeem which should be summed
    par.requestRedeem(scaledAmount / 2);
    assertEq(queue.userWithdrawalsEpochs(address(this), epochNumber), scaledAmount, 'user withdrawal epoch should be increased');
    assertEq(queue.epochPending(epochNumber), scaledAmount, 'epoch pending should be increased');
    assertEq(queue.totReservedWithdrawals(), scaledAmount, 'total reserved withdrawals should be increased');
    vm.stopPrank();
  }

  function testRequestRedeemMultipleEpochs() external {
    uint256 epochNumber = queue.epochNumber();
    // deposit 100 USDC in the vault
    uint256 amount = 100e6;
    uint256 scaledAmount = amount * 10 ** 12; // should be scaled to 18 decimals
    _mintUSP(address(this), USDC, amount);

    vm.startPrank(address(this));
    par.requestRedeem(scaledAmount / 2);

    assertEq(queue.userWithdrawalsEpochs(address(this), epochNumber), scaledAmount / 2, 'user withdrawal epoch should be updated');
    assertEq(queue.epochPending(epochNumber), scaledAmount / 2, 'epoch pending should be updated');
    assertEq(queue.totReservedWithdrawals(), scaledAmount / 2, 'total reserved withdrawals should be updated');

    // update epoch
    stdstore
      .target(address(queue))
      .sig(queue.epochNumber.selector)
      .checked_write(epochNumber + 1);

    par.requestRedeem(scaledAmount / 2);

    assertEq(queue.userWithdrawalsEpochs(address(this), epochNumber + 1), scaledAmount / 2, 'user withdrawal epoch should be updated for another epoch');
    assertEq(queue.epochPending(epochNumber + 1), scaledAmount / 2, 'epoch pending should be updated for another epoch');
    assertEq(queue.totReservedWithdrawals(), scaledAmount, 'total reserved withdrawals should be updated for another epoch');

    vm.stopPrank();
  }

  function testCallWhitelistedMethods() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), queue.MANAGER_ROLE()));
    queue.callWhitelistedMethods(new address[](0), new bytes4[](0), new bytes[](0));

    vm.startPrank(TL_MULTISIG);
    // call with parameters with different length should revert
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.callWhitelistedMethods(new address[](0), new bytes4[](1), new bytes[](0));
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.callWhitelistedMethods(new address[](1), new bytes4[](0), new bytes[](1));
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.callWhitelistedMethods(new address[](1), new bytes4[](1), new bytes[](0));

    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = FAS_USDC_CV;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = bytes4(keccak256(bytes("evilMethod(uint256)")));
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(100e6);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotAllowed.selector));
    queue.callWhitelistedMethods(sources, methods, args);
    vm.stopPrank();

    // we are going to test that we can request a redeem in a credit vault

    // deposit 100 USDC in the ParetoDollar
    uint256 amount = 100e6;
    _mintUSP(address(this), USDC, amount);
    // manager deposit funds in credit vault
    _depositFundsCV(FAS_USDC_CV, amount);

    address aaTranche = IIdleCDOEpochVariant(FAS_USDC_CV).AATranche();
    IIdleCreditVault strategy = IIdleCreditVault(IIdleCDOEpochVariant(FAS_USDC_CV).strategy());
    uint256 trancheAmount = IERC20Metadata(aaTranche).balanceOf(address(queue));

    // manager request a redeem
    methods[0] = WITHDRAW_AA_SIG;
    args[0] = abi.encode(trancheAmount, aaTranche);
    vm.startPrank(TL_MULTISIG);
    vm.expectEmit(true, true, true,true);
    emit IParetoDollarQueue.YieldSourceCall(sources[0], methods[0], args[0]);
    queue.callWhitelistedMethods(sources, methods, args);

    assertEq(IERC20Metadata(aaTranche).balanceOf(address(queue)), 0, 'queue should not have any AA tranche');
    assertApproxEqAbs(
      strategy.withdrawsRequests(address(queue)), 
      amount,
      1,
      'credit vault should have the withdraw request'
    );
    vm.stopPrank();
  }

  function testRedeemFunds() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), queue.MANAGER_ROLE()));
    queue.redeemFunds(new address[](0), new bytes4[](0), new bytes[](0), 1);

    uint256 epoch = queue.epochNumber();

    vm.startPrank(TL_MULTISIG);
    // call with parameters with different length should revert
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.redeemFunds(new address[](0), new bytes4[](1), new bytes[](0), 1);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.redeemFunds(new address[](1), new bytes4[](0), new bytes[](1), 1);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.redeemFunds(new address[](1), new bytes4[](1), new bytes[](0), 1);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.Invalid.selector));
    queue.redeemFunds(new address[](1), new bytes4[](1), new bytes[](1), epoch + 1);

    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = FAS_USDC_CV;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = bytes4(keccak256(bytes("evilMethod(uint256)")));
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(100e6);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotAllowed.selector));
    queue.redeemFunds(sources, methods, args, 1);
    vm.stopPrank();

    // we are going to test that we can claim a redeem request in a credit vault

    uint256 amount = 100e6;
    // mint USP
    _mintUSP(address(this), USDC, amount);
    // manager deposits collateral in CV
    uint256 trancheAmount = _depositFundsCV(FAS_USDC_CV, amount);
    // manager request redeems
    _requestRedeemCV(FAS_USDC_CV, trancheAmount);
    // we start and then stop the CV epoch so we can claim the requested amount
    _rollEpochCV(FAS_USDC_CV);

    // claim the funds previously requested from CV
    uint256 balPre = IERC20Metadata(USDC).balanceOf(address(queue));
    sources[0] = FAS_USDC_CV;
    methods[0] = CLAIM_REQ_SIG;
    args[0] = abi.encode();

    vm.startPrank(TL_MULTISIG);
    vm.expectEmit(true, true, true, true);
    // amount - 1 for rounding
    emit IParetoDollarQueue.YieldSourceRedeem(FAS_USDC_CV, USDC, amount - 1);
    queue.redeemFunds(sources, methods, args, 0);
    vm.stopPrank();

    assertApproxEqAbs(IERC20Metadata(USDC).balanceOf(address(queue)) - balPre, amount, 1, 'queue should bal eq to the amount redeemed');
    assertEq(queue.epochPending(epoch), 0, 'epoch pending should be eq to 0');
  }

  function testRedeemFundsWithPendingRequests() external {
    uint256 amount = 100e6;
    address user1 = makeAddr('user1');
    // mint USP
    uint256 minted = _mintUSP(address(this), USDC, amount);
    uint256 minted1 = _mintUSP(user1, USDC, amount);
    // manager deposits collateral in CV
    uint256 trancheAmount = _depositFundsCV(FAS_USDC_CV, amount * 2);
    uint256 epoch = queue.epochNumber();
    // request USP redeem from address(this)
    _requestRedeemUSP(address(this), minted);
    assertEq(queue.epochPending(epoch), minted, 'Epoch pending should be updated');
    // manager stops queue epoch so redeems can be processed
    _stopEpoch();
    // manager request redeems for half of the requested amount and then claim from CV after an epoch
    _getFundsFromCV(FAS_USDC_CV, trancheAmount / 4, epoch);
    assertApproxEqAbs(queue.getYieldSource(FAS_USDC_CV).depositedAmount, amount + amount / 2, 1, 'Vault deposited amount should be updated');
    // we scale the value back to 6 decimals for correct comparison
    assertApproxEqAbs(queue.epochPending(epoch), minted / 2, 1e12, 'Epoch pending should be halved');

    // request USP redeem for user1 for the whole amount
    _requestRedeemUSP(user1, minted1);
    // get funds from CV for the entire deposited amount
    _getFundsFromCV(FAS_USDC_CV, trancheAmount * 3 / 4, epoch);

    assertEq(queue.epochPending(epoch), 0, 'Epoch pending should be 0');
  }

  function testRedeemRoundingIssues() external {
    uint256 amount = 100e6;
    // mint USP
    uint256 minted = _mintUSP(address(this), USDC, amount);
    // manager deposits collateral in CV
    uint256 trancheAmount = _depositFundsCV(FAS_USDC_CV, amount);
    uint256 epoch = queue.epochNumber();
    // request USP redeem from address(this)
    _requestRedeemUSP(address(this), minted);
    // manager stops queue epoch so redeems can be processed
    _stopEpoch();
    // manager request redeems for half of the requested amount and then claim from CV after an epoch
    _getFundsFromCV(FAS_USDC_CV, trancheAmount, epoch);
    // we scale the value back to 6 decimals for correct comparison. There is 1 wei difference (scaled)
    assertApproxEqAbs(queue.epochPending(epoch), 0, 1e12, 'Epoch pending should be almost 0');

    // cannot call stopEpoch again as long as epochPending is > 0
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotReady.selector));
    _stopEpoch();

    // manager should send some funds to the contract (or use new deposits)
    // to 'reset' epochPending.
    // let's deposit funds with another user
    _mintUSP(address(987), USDC, amount);
    // the -1 is to 'fix' the 1 wei on epochPending
    _depositFundsCV(FAS_USDC_CV, amount - 1);

    // same can be achieved via donation + depositFunds(0)
    // _donate(USDC, address(queue), 1);
    // _depositFundsCV(FAS_USDC_CV, 0);

    // now we can call stopEpoch
    _stopEpoch();
  }

  function testClaimRedeemRequest() external {
    // allow anyone to use ParetoDollar
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);

    // only ParetoDollar can call this
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotAllowed.selector));
    queue.claimRedeemRequest(address(this), 1e6);
    // claim for the current epoch
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotReady.selector));
    par.claimRedeemRequest(1);
    // claim with a user that has no deposits for prev epoch
    uint256 amountRequested = par.claimRedeemRequest(0);
    assertEq(amountRequested, 0, 'user should not have any redeem request');

    uint256 epoch = queue.epochNumber();
    uint256 amount = 100e6;
    // deposit 100 USDC in the ParetoDollar
    uint256 minted = _mintUSP(address(this), USDC, amount);
    // request redeem
    _requestRedeemUSP(address(this), minted);
    assertEq(queue.userWithdrawalsEpochs(address(this), epoch), minted, 'user withdrawal epoch should be eq to the amount requested');
    assertEq(queue.totReservedWithdrawals(), minted, 'totReservedWithdrawals should be the amount requested');
    // update epoch
    _stopEpoch();
    // cannot claim as long as epochPending is not 0 (ie depositFunds/redeemFunds should have been called at least once)
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotReady.selector));
    par.claimRedeemRequest(epoch);
    // manager deposits 0 funds in CV (all funds - funds requested for redeems) so that epochPending is set to 0
    _depositFundsCV(FAS_USDC_CV, 0);
    assertEq(queue.epochPending(epoch), 0, 'epoch pending should be eq to 0');

    // we simulate a loss to trigger InsufficientBalance error
    vm.prank(address(queue));
    IERC20Metadata(USDC).safeTransfer(address(2), 1);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.InsufficientBalance.selector));
    par.claimRedeemRequest(epoch);
    // we give the token back to the contract 
    vm.prank(address(2));
    IERC20Metadata(USDC).safeTransfer(address(queue), 1);

    // claim the funds previously requested from CV
    uint256 balPre = IERC20Metadata(USDC).balanceOf(address(this));
    uint256 redeemed = par.claimRedeemRequest(epoch);
    assertApproxEqAbs(IERC20Metadata(USDC).balanceOf(address(this)) - balPre, amount, 1, 'user should have the amount redeemed');
    assertEq(queue.userWithdrawalsEpochs(address(this), epoch), 0, 'user withdrawal epoch should be 0');
    assertEq(queue.totReservedWithdrawals(), 0, 'totReservedWithdrawals should be 0');
    assertEq(redeemed, minted, 'return value should be the amount redeemed');
  }

  function testStopEpoch() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), queue.MANAGER_ROLE()));
    queue.stopEpoch();

    // epoch 1
    uint256 epoch = queue.epochNumber();
    vm.startPrank(TL_MULTISIG);
    vm.expectEmit(true, true, true,true);
    emit IParetoDollarQueue.NewEpoch(epoch + 1);
    queue.stopEpoch();
    vm.stopPrank();
    assertEq(queue.epochNumber(), epoch + 1, 'epoch number should be incremented');

    uint256 amount = 100e6;
    // mint USP
    uint256 minted = _mintUSP(address(this), USDC, amount);
    // request USP redeem
    _requestRedeemUSP(address(this), minted);

    vm.startPrank(TL_MULTISIG);
    // epoch is now 3
    queue.stopEpoch();
    epoch = queue.epochNumber();
    // cannot go to epoch 4 because epoch 2 has not all redeem requests fulfilled
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.NotReady.selector));
    queue.stopEpoch();
    vm.stopPrank();
    assertEq(queue.epochNumber(), epoch, 'epoch number should be the same');
  }

  function testDepositFundsWithPendingRequests() external {
    uint256 amount = 100e6;
    uint256 minted = _mintUSP(address(this), USDC, amount);
    uint256 epoch = queue.epochNumber();
    // request redeem
    _requestRedeemUSP(address(this), minted);
    // epochPending[1] is now 100e18
    assertEq(queue.epochPending(epoch), amount * 10**12, 'Epoch pending should be set to the amount requested (scaled)');

    // another user deposits
    _mintUSP(address(1), USDC, amount);
    _stopEpoch();
    // manager tries to deposit all funds but cannot because there are pending requests
    vm.expectRevert(abi.encodeWithSelector(IParetoDollarQueue.InsufficientBalance.selector));
    _depositFundsCV(FAS_USDC_CV, amount * 2);
    // manager deposits only the amount that is not pending, epoch pending will be reset
    _depositFundsCV(FAS_USDC_CV, amount);
    assertEq(queue.epochPending(epoch), 0, 'Epoch pending should be set to 0');
  }

  function testGetTotalCollateralsScaled() external {
    assertEq(queue.getTotalCollateralsScaled(), 0, 'totCollaterals is 0 initially');
    // deposit 100 USDC in the ParetoDollar
    uint256 amount = 100e6;
    _mintUSP(address(this), USDC, amount);
    assertEq(queue.getTotalCollateralsScaled(), 100 * 1e18, 'totCollaterals is not considering unlent balance');
    // deposit in CV half of the funds
    _depositFundsCV(FAS_USDC_CV, amount / 2);
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 100 * 1e18, 1, 'totCollaterals value after CV deposit is not correct');
    // deposit additional 100 USDC
    _mintUSP(address(123), USDC, amount);
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 200 * 1e18, 1, 'totCollaterals value after second deposit is not correct');
    // deposit in CV all funds
    uint256 trancheAmount = _depositFundsCV(FAS_USDC_CV, amount / 2 + amount);
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 200 * 1e18, 2, 'totCollaterals value after second CV deposit is not correct');
    // redeem all funds from CV
    _getFundsFromCV(FAS_USDC_CV, trancheAmount, 1);
    // diff is 1e12 (ie 1 wei of a token with 6 decimals scaled to 1e18)
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 200 * 1e18, 1e12, 'totCollaterals value after CV redeem is not correct');
    // get USDS for half of the total amount
    _sellUSDCPSM(amount);
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 200 * 1e18, 1e12, 'totCollaterals value after USDS buy is not correct');
    uint256 scaleFactor = 10 ** 12; // 10 ** (18 - USDC.decimals())
    // deposit all USDS to get SUSDS
    uint256 sUSDS = _deposit4626(SUSDS, amount * scaleFactor);
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 200 * 1e18, 1e12 + 1, 'totCollaterals value after SUSDS deposit is not correct');
    // redeem all from SUSDS
    _redeem4626(SUSDS, sUSDS, 1);
    assertApproxEqAbs(queue.getTotalCollateralsScaled(), 200 * 1e18, 1e12 + 1, 'totCollaterals value after SUSDS redeem is not correct');
  }

  function testDepositYield() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), queue.MANAGER_ROLE()));
    queue.depositYield();

    // set sPar fees to 0 to ease calculations
    vm.startPrank(sPar.owner());
    sPar.updateFeeParams(0, address(1));
    vm.stopPrank();

    _depositYield();
    assertEq(par.totalSupply(), 0, 'total supply should not change if there is no new collateral');

    // deposit 100 USDC in the ParetoDollar
    uint256 amount = 100e6;
    _mintUSP(address(this), USDC, amount);
    uint256 initialSupply = par.totalSupply();

    _depositYield();
    assertEq(par.totalSupply(), initialSupply, 'total supply should not change if there is no yield');

    uint256 trancheTokens = _depositFundsCV(FAS_USDC_CV, amount);
    assertEq(par.totalSupply(), initialSupply, 'total supply should not change after depositing in CV');

    IIdleCDOEpochVariant cv = IIdleCDOEpochVariant(FAS_USDC_CV);
    uint256 pricePre = cv.virtualPrice(cv.AATranche());
    // Increase CV price by donating assets to it
    _donate(USDC, FAS_USDC_CV, amount * 100);
    uint256 pricePost = cv.virtualPrice(cv.AATranche());
    assertGt(pricePost, pricePre, 'CV price should increase after donation');
    uint256 priceDiff = pricePost - pricePre;
    uint256 gainScaled18 = trancheTokens * priceDiff / 1e6;

    _depositYield();

    assertApproxEqAbs(par.totalSupply(), initialSupply + gainScaled18, 1, 'total supply should increase by the yield gained');
  }

  function testPSMInteractions() external {
    // deposit 100 USDC in the ParetoDollar
    uint256 amount = 100e6;
    _mintUSP(address(this), USDC, amount);

    // use PSM to swap 100 USDC for 100 USDS  
    _sellUSDCPSM(amount);
    assertEq(IERC20Metadata(USDS).balanceOf(address(queue)), 100 * 1e18, 'queue should have 100 USDS');
    assertEq(IERC20Metadata(USDC).balanceOf(address(queue)), 0, 'queue should not have USDC');

    // use PSM to swap 100 USDS for 100 USDC. 
    // Amount must be passed in USDC
    _buyUSDCPSM(amount);
    assertEq(IERC20Metadata(USDS).balanceOf(address(queue)), 0, 'queue should not have USDS');
    assertEq(IERC20Metadata(USDC).balanceOf(address(queue)), amount, 'queue should have 100 USDC');
  }

  function _depositYield() internal {
    vm.prank(TL_MULTISIG);
    queue.depositYield();
  }

  function _mintUSP(address _user, address _collateral, uint256 _amount) internal returns (uint256 mintedAmount) {
    // allow anyone to mint
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);
    // mint USP
    deal(_collateral, _user, _amount);
    vm.startPrank(_user);
    IERC20Metadata(_collateral).safeIncreaseAllowance(address(par), _amount);
    mintedAmount = par.mint(_collateral, _amount);
    vm.stopPrank(); 
  }

  function _requestRedeemUSP(address _user, uint256 _amount) internal {
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);

    vm.prank(_user);
    par.requestRedeem(_amount);
  }

  function _stopEpoch() internal {
    vm.prank(TL_MULTISIG);
    queue.stopEpoch();
  }

  /// @notice call queue.depositFunds
  function _depositFundsCV(address source, uint256 amount) internal returns (uint256 trancheAmount) {
    // call with method not allowed should revert 
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = DEPOSIT_AA_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(amount);
    vm.prank(TL_MULTISIG);
    queue.depositFunds(sources, methods, args);

    address aaTranche = IIdleCDOEpochVariant(FAS_USDC_CV).AATranche();
    return IERC20Metadata(aaTranche).balanceOf(address(queue));
  }

  /// @notice deposit in ERC4626 vault
  function _deposit4626(address source, uint256 amount) internal returns (uint256 amount4626) {
    // call with method not allowed should revert 
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = DEPOSIT_4626_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(amount, address(queue));
    vm.prank(TL_MULTISIG);
    queue.depositFunds(sources, methods, args);

    // source is usually the erc4626 token itself
    return IERC20Metadata(source).balanceOf(address(queue));
  }

  /// @notice redeem from ERC4626 vault
  function _redeem4626(address source, uint256 shares, uint256 _epoch) internal returns (uint256) {
    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = REDEEM_4626_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(shares, address(queue), address(queue));
    vm.prank(TL_MULTISIG);
    queue.redeemFunds(sources, methods, args, _epoch);

    return IERC20Metadata(IERC4626(source).asset()).balanceOf(address(queue));
  }

  // buy USDC with USDS via PSM
  function _buyUSDCPSM(uint256 amount) internal {
    // call with method not allowed should revert 
    address[] memory sources = new address[](1);
    sources[0] = USDS_USDC_PSM;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = BUY_GEM_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(address(queue), amount);
    vm.prank(TL_MULTISIG);
    queue.callWhitelistedMethods(sources, methods, args);
  }

  // sell USDC for USDS via PSM
  function _sellUSDCPSM(uint256 amount) internal {
    // call with method not allowed should revert 
    address[] memory sources = new address[](1);
    sources[0] = USDS_USDC_PSM;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = SELL_GEM_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(address(queue), amount);
    vm.prank(TL_MULTISIG);
    queue.callWhitelistedMethods(sources, methods, args);
  }

  /// @notice call queue.callWhitelistedMethods
  /// @dev amount should be in tranche tokens
  function _requestRedeemCV(address source, uint256 trancheAmount) internal {
    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = WITHDRAW_AA_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(trancheAmount, IIdleCDOEpochVariant(source).AATranche());
    vm.prank(TL_MULTISIG);
    queue.callWhitelistedMethods(sources, methods, args);
  }

  /// @notice call queue.redeemFunds to claim a redeem request in a CV
  function _claimRedeemRequestCV(address source, uint256 _epoch) internal {
    // call with method not allowed should revert
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = CLAIM_REQ_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode();
    vm.prank(TL_MULTISIG);
    queue.redeemFunds(sources, methods, args, _epoch);
  }

  /// @notice start/stop epoch in CV
  function _toggleEpochCV(address source, bool _start) internal {
    IIdleCDOEpochVariant _vault = IIdleCDOEpochVariant(address(source));
    IIdleCreditVault strategy = IIdleCreditVault(_vault.strategy());
    address _owner = IIdleCreditVault(_vault.strategy()).manager();
    address _token = _vault.token();
    uint256 unscaledApr = strategy.unscaledApr();
    if (_start) {
      if (_vault.epochEndDate() != 0) {
        vm.warp(block.timestamp + _vault.bufferPeriod() + 1);
      }
      vm.prank(_owner);
      _vault.startEpoch();
    } else {
      uint256 expectedFunds = _vault.expectedEpochInterest() + strategy.pendingWithdraws();
      deal(_token, strategy.borrower(), expectedFunds);
      vm.startPrank(strategy.borrower());
      IERC20Metadata(_token).safeIncreaseAllowance(address(_vault), expectedFunds);
      vm.stopPrank();
      vm.warp(_vault.epochEndDate() + 1);
      vm.prank(_owner);
      _vault.stopEpoch(unscaledApr, 0);
      assertEq(_vault.defaulted(), false, 'borrower should not be defaulted');
    }
  }

    /// @notice start and then stop an epoch in a source CV
  function _rollEpochCV(address source) internal {
    _toggleEpochCV(source, true);
    _toggleEpochCV(source, false);
  }

  /// @notice request and then claim funds from a CV
  function _getFundsFromCV(address source, uint256 trancheAmount, uint256 epoch) internal {
    // manager request redeems for half of the requested amount
    _requestRedeemCV(source, trancheAmount);
    // we start and then stop the CV epoch so we can claim the requested amount
    _rollEpochCV(source);
    // claim requested funds from CV
    _claimRedeemRequestCV(source, epoch);
  }

  /// @notice function used instead of direct deal which overwrite current balance instead of increasing it
  function _donate(address _token, address _to, uint256 _amount) internal {
    address _user = makeAddr('user1234');
    deal(_token, _user, _amount);
    vm.startPrank(_user);
    IERC20Metadata(_token).safeTransfer(_to, _amount);    
    vm.stopPrank();
  }
}