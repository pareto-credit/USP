// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { ParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { IParetoDollar } from "../src/interfaces/IParetoDollar.sol";
import { IPriceFeed } from "../src/interfaces/IPriceFeed.sol";
import { IKeyring } from "../src/interfaces/IKeyring.sol";
import { DeployScript, Constants } from "../script/Deploy.s.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TestParetoDollarStaking is Test, DeployScript {
  using SafeERC20 for IERC20Metadata;
  ParetoDollar par;
  ParetoDollarStaking sPar;
  ParetoDollarQueue queue;

  event RewardsDeposited(uint256 amount);

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par, sPar, queue) = _deploy(false);
    vm.stopPrank();

    skip(100);
  }

  function testInitialize() external view {
    assertEq(sPar.name(), 'Pareto staked USP', 'name is wrong');
    assertEq(sPar.symbol(), 'sUSP', 'symbol is wrong');
    assertEq(sPar.owner(), TL_MULTISIG, 'owner is wrong');
    assertEq(sPar.decimals(), 18, 'decimals is wrong');
    assertEq(sPar.rewardsVesting(), 7 days, 'rewardsVesting is wrong');
    assertEq(sPar.fee(), 5_000, 'fee is wrong');
    assertEq(sPar.feeReceiver(), TL_MULTISIG, 'feeReceiver is wrong');

    assertEq(sPar.totalSupply(), 0, 'totalSupply is wrong');
    assertEq(sPar.balanceOf(TL_MULTISIG), 0, 'DEPLOYER balance is wrong');

    assertEq(sPar.hasRole(sPar.DEFAULT_ADMIN_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have DEFAULT_ADMIN_ROLE');
    assertEq(sPar.hasRole(sPar.PAUSER_ROLE(), HYPERNATIVE_PAUSER), true, 'HYPERNATIVE_PAUSER should have PAUSER_ROLE');
    assertEq(sPar.hasRole(sPar.PAUSER_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have PAUSER_ROLE');
    assertEq(sPar.hasRole(sPar.MANAGER_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have MANAGER_ROLE');
    assertEq(sPar.isPausable(), true, 'the contract should be pausable');
  }

  function testEmergencyWithdraw() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    sPar.emergencyWithdraw(address(1), 1);

    deal(USDC, address(sPar), 100);

    uint256 balPre = IERC20Metadata(USDC).balanceOf(sPar.owner());

    vm.startPrank(sPar.owner());
    sPar.emergencyWithdraw(USDC, 100);
    uint256 balPost = IERC20Metadata(USDC).balanceOf(sPar.owner());
    assertEq(balPost, balPre + 100, 'owner balance should increase by 100');
    vm.stopPrank();
  }

  function testPause() external {
    _stake(address(this), 1e18);

    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), sPar.PAUSER_ROLE()));
    sPar.pause();

    vm.startPrank(sPar.owner());
    sPar.pause();
    assertEq(sPar.paused(), true, 'The contract should be paused');

    // when paused no deposits or redeems can be made
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    sPar.deposit(1e18, address(this));
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    sPar.redeem(1e18, address(this), address(this));
    vm.stopPrank();
  }

  function testRoles() external {
    bytes32 manager = sPar.MANAGER_ROLE();
    bytes32 pauser = sPar.PAUSER_ROLE();
    bytes32 defaultAdmin = sPar.DEFAULT_ADMIN_ROLE();

    bytes memory defaultError = abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdmin);

    // if non admin tries to grant role, it reverts
    vm.expectRevert(defaultError);
    sPar.grantRole(manager, address(this));
    vm.expectRevert(defaultError);
    sPar.grantRole(pauser, address(this));
    vm.expectRevert(defaultError);
    sPar.grantRole(defaultAdmin, address(this));

    // if non admin tries to removke role, it reverts
    vm.expectRevert(defaultError);
    sPar.revokeRole(manager, address(this));
    vm.expectRevert(defaultError);
    sPar.revokeRole(pauser, address(this));
    vm.expectRevert(defaultError);
    sPar.revokeRole(defaultAdmin, address(this));

    // admin can grant roles
    address admin = TL_MULTISIG;
    vm.startPrank(admin);
    sPar.grantRole(manager, address(this));
    sPar.grantRole(pauser, address(this));
    sPar.grantRole(defaultAdmin, address(this));
    assertEq(sPar.hasRole(manager, address(this)), true, 'address(this) should have MANAGER_ROLE');
    assertEq(sPar.hasRole(pauser, address(this)), true, 'address(this) should have PAUSER_ROLE');
    assertEq(sPar.hasRole(defaultAdmin, address(this)), true, 'address(this) should have DEFAULT_ADMIN_ROLE');
    vm.stopPrank();

    // admin can revoke roles
    vm.startPrank(admin);
    sPar.revokeRole(manager, address(this));
    sPar.revokeRole(pauser, address(this));
    sPar.revokeRole(defaultAdmin, address(this));
    assertEq(sPar.hasRole(manager, address(this)), false, 'address(this) should not have MANAGER_ROLE');
    assertEq(sPar.hasRole(pauser, address(this)), false, 'address(this) should not have PAUSER_ROLE');
    assertEq(sPar.hasRole(defaultAdmin, address(this)), false, 'address(this) should not have DEFAULT_ADMIN_ROLE');
    vm.stopPrank();
  }

  function testUnpause() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    sPar.unpause();

    vm.startPrank(sPar.owner());
    sPar.pause();
    sPar.unpause();

    assertEq(sPar.paused(), false, 'The contract should not be paused');
    vm.stopPrank();
  }

  function testDeposit() external {
    uint256 depositAmount = 1e18;
    _stake(address(this), depositAmount);

    uint256 balPost = sPar.balanceOf(address(this));
    // sPar is minted 1:1 if there is no interest accrued
    assertEq(balPost, depositAmount, 'Balance should reflect the deposit amount');
  }

  function testRedeem() external {
    uint256 depositAmount = 1e18;
    _stake(address(this), depositAmount);

    uint256 balPre = par.balanceOf(address(this));
    // sPar is redeemed 1:1 if there is no interest
    sPar.redeem(depositAmount, address(this), address(this));
    uint256 balPost = par.balanceOf(address(this));

    assertEq(sPar.balanceOf(address(this)), 0, 'sPar balance should be 0');
    assertEq(balPost, balPre + depositAmount, 'Balance should reflect the deposit amount');
  }

  function testRedeemWithInterest() external {
    uint256 depositAmount = 1e18;
    uint256 shares = _stake(address(this), depositAmount);

    // set fees to 0
    vm.prank(sPar.owner());
    sPar.updateFeeParams(0, address(this));

    // give sPar some interest by depositing par tokens directly
    give(address(par), address(sPar), depositAmount);
    assertApproxEqAbs(sPar.convertToAssets(shares), depositAmount * 2, 1, 'Balance should reflect the deposit amount + interest');
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 2, 1, 'Total assets should reflect the deposit amount + interest');

    depositRewards(depositAmount);
    assertApproxEqAbs(sPar.convertToAssets(shares), depositAmount * 2, 1, 'Balance should be equal then before because rewards are not vested yet');
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 2, 1, 'Total assets should be equal then before because rewards are not vested yet');

    skip(sPar.rewardsVesting() / 2);
    assertApproxEqAbs(sPar.convertToAssets(shares), depositAmount * 25 / 10, 2, 'Balance should have rewards half vested');
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 25 / 10, 2, 'Total assets should have rewards half vested');

    skip(sPar.rewardsVesting() / 2 + 1);
    assertApproxEqAbs(sPar.convertToAssets(shares), depositAmount * 3, 2, 'Balance should have rewards fully vested');
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 3, 2, 'Total assets should have rewards fully vested');

    sPar.redeem(depositAmount, address(this), address(this));
    assertApproxEqAbs(par.balanceOf(address(this)), depositAmount * 3, 2, 'Balance should reflect the deposit amount + interest and vested rewards');
  }

  function testDepositRewards() external {
    uint256 depositAmount = 1e18;
    _stake(address(this), depositAmount);

    // set fees to 0
    vm.prank(sPar.owner());
    sPar.updateFeeParams(0, address(this));

    depositRewards(depositAmount);

    assertEq(sPar.rewards(), depositAmount, 'Rewards should be deposited');
    assertEq(sPar.rewardsLastDeposit(), block.timestamp, 'RewardsLastDeposit should be updated');

    assertApproxEqAbs(sPar.totalAssets(), depositAmount, 1, 'Total assets should have no rewards vested');
    // we only vest half of the rewards
    skip(sPar.rewardsVesting() / 2);
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 15 / 10, 1, 'Total assets have prev rewards partially vested');

    // we deposit again before the end of the vesting period, prev rewards are now fully vested
    depositRewards(depositAmount);
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 2, 1, 'Total assets have prev rewards fully vested');
    assertEq(sPar.rewards(), depositAmount, 'New rewards should be deposited');
    assertEq(sPar.rewardsLastDeposit(), block.timestamp, 'RewardsLastDeposit should be updated again');

    skip(sPar.rewardsVesting() / 2);
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 25 / 10, 1, 'Total assets have second tranche of rewards partially vested');

    skip(sPar.rewardsVesting() / 2);
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 3, 1, 'Total assets have second tranche of rewards fully vested');

    // deposit rewards cannot be called by non managers
    vm.startPrank(address(this));
    vm.expectRevert(abi.encodeWithSelector(ParetoDollarStaking.NotAllowed.selector));
    sPar.depositRewards(depositAmount);
    vm.stopPrank();

    // set fees to 10%
    address feeReceiver = makeAddr('feeReceiver');
    vm.startPrank(sPar.owner());
    sPar.updateFeeParams(sPar.FEE_100() / 10, feeReceiver);
    vm.stopPrank();
    
    uint256 depositAmount2 = 1e18;
    depositRewards(depositAmount2);
    uint256 expectedFees = depositAmount2 / 10;
    uint256 expectedRewards = depositAmount2 - expectedFees;

    assertEq(sPar.rewards(), expectedRewards, 'Rewards should be deposited and fees should be taken');
    assertEq(par.balanceOf(feeReceiver), expectedFees, 'Fees should be transferred to feeReceiver');

    skip(sPar.rewardsVesting() + 1);
    assertApproxEqAbs(sPar.totalAssets(), depositAmount * 39 / 10, 1, 'Total assets have rewards vested minus fee');
  }

  function testUpdateRewardsVesting() external {
    vm.prank(sPar.owner());
    sPar.updateRewardsVesting(2 days);
    assertEq(sPar.rewardsVesting(), 2 days, 'RewardsVesting should be 2 days');

    // test with non owner
    vm.prank(address(this));
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    sPar.updateRewardsVesting(1 days);
  }

  function testUpdateFeeParams() external {
    vm.prank(sPar.owner());
    sPar.updateFeeParams(1_000, address(this));
    assertEq(sPar.fee(), 1_000, 'Fee should be 1_000');
    assertEq(sPar.feeReceiver(), address(this), 'FeeReceiver should be address(this)');

    // test with non owner
    vm.prank(address(this));
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    sPar.updateFeeParams(1_000, address(this));

    // test fee too high
    uint256 maxFee = sPar.MAX_FEE();
    vm.prank(sPar.owner());
    vm.expectRevert(bytes4(keccak256("FeeTooHigh()")));
    sPar.updateFeeParams(maxFee + 1, address(this));
  }

  function _stake(address _who, uint256 _amount) internal returns (uint256 shares) {
    deal(address(par), address(_who), _amount);
    vm.startPrank(_who);
    par.approve(address(sPar), _amount);
    shares = sPar.deposit(_amount, _who);
    vm.stopPrank();
  }

  function depositRewards(uint256 _amount) internal {
    give(address(par), address(queue), _amount);
    uint256 expectedFees = _amount * sPar.fee() / sPar.FEE_100();
    uint256 expectedRewards = _amount - expectedFees;

    vm.startPrank(address(queue));
    par.approve(address(sPar), _amount);
    vm.expectEmit(address(sPar));
    emit RewardsDeposited(expectedRewards);
    sPar.depositRewards(_amount);
    vm.stopPrank();
  }

  // donate assets (ie increase balance of _who)
  function give(address _token, address _who, uint256 _amount) internal {
    deal(_token, address(1), _amount);
    vm.prank(address(1));
    IERC20Metadata(_token).safeTransfer(_who, _amount);
  }
}