// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarStaking } from "../src/ParetoDollarStaking.sol";
import { IParetoDollar } from "../src/interfaces/IParetoDollar.sol";
import { IPriceFeed } from "../src/interfaces/IPriceFeed.sol";
import { IKeyring } from "../src/interfaces/IKeyring.sol";
import { DeployScript, Constants } from "../script/Deploy.s.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TestParetoDollarStaking is Test, DeployScript {
  using SafeERC20 for IERC20Metadata;
  ParetoDollar par;
  ParetoDollarStaking sPar;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par, sPar) = _deploy(false);
    vm.stopPrank();

    skip(100);
  }

  function testInitialize() external view {
    assertEq(sPar.name(), 'Pareto staked USP', 'name is wrong');
    assertEq(sPar.symbol(), 'sUSP', 'symbol is wrong');
    assertEq(sPar.owner(), DEPLOYER, 'owner is wrong');
    assertEq(sPar.decimals(), 18, 'decimals is wrong');

    assertEq(sPar.totalSupply(), 0, 'totalSupply is wrong');
    assertEq(sPar.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');
  }

  function testEmergencyWithdraw() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    sPar.emergencyWithdraw(address(1), 1);

    deal(USDC, address(sPar), 100);

    uint256 balPre = IERC20Metadata(USDC).balanceOf(DEPLOYER);

    vm.startPrank(sPar.owner());
    sPar.emergencyWithdraw(USDC, 100);
    uint256 balPost = IERC20Metadata(USDC).balanceOf(DEPLOYER);
    assertEq(balPost, balPre + 100, 'DEPLOYER balance should increase by 100');
    vm.stopPrank();
  }

  function testPause() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    sPar.pause();

    vm.startPrank(sPar.owner());
    sPar.pause();
    assertEq(sPar.paused(), true, 'The contract should be paused');
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
    _stake(address(this), depositAmount);

    // give sPar some interest by depositing par tokens directly
    give(address(par), address(sPar), depositAmount);
    sPar.redeem(depositAmount, address(this), address(this));
    uint256 balPost = par.balanceOf(address(this));

    assertApproxEqAbs(balPost, depositAmount * 2, 1, 'Balance should reflect the deposit amount + interest');
  }

  function _stake(address _who, uint256 _amount) internal {
    deal(address(par), address(_who), _amount);
    vm.startPrank(_who);
    par.approve(address(sPar), _amount);
    sPar.deposit(_amount, _who);
    vm.stopPrank();
  }

  function give(address _token, address _who, uint256 _amount) internal {
    deal(_token, address(1), _amount);
    vm.prank(address(1));
    IERC20Metadata(_token).safeTransfer(_who, _amount);
  }
}