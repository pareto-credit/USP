// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { ParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { IParetoDollar } from "../src/interfaces/IParetoDollar.sol";
import { IParetoDollarQueue } from "../src/interfaces/IParetoDollarQueue.sol";
import { IPriceFeed } from "../src/interfaces/IPriceFeed.sol";
import { IKeyring } from "../src/interfaces/IKeyring.sol";
import { DeployScript, Constants } from "../script/Deploy.s.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TestParetoDollar is Test, DeployScript {
  using SafeERC20 for IERC20Metadata;
  ParetoDollar par;
  ParetoDollarQueue queue;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par,,queue) = _deploy(false);
    vm.stopPrank();

    skip(100);
  }

  function testInitialize() external view {
    assertEq(par.name(), 'Pareto synthetic dollar USP', 'name is wrong');
    assertEq(par.symbol(), 'USP', 'symbol is wrong');
    assertEq(par.owner(), TL_MULTISIG, 'owner is wrong');

    assertEq(par.totalSupply(), 0, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');
    assertEq(par.balanceOf(TL_MULTISIG), 0, 'TL_MULTISIG balance is wrong');

    assertEq(par.keyring(), KEYRING_WHITELIST, 'keyring is wrong');
    assertEq(par.keyringPolicyId(), KEYRING_POLICY, 'keyring policy is wrong');
    assertEq(par.hasRole(par.DEFAULT_ADMIN_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have DEFAULT_ADMIN_ROLE');
    assertEq(par.hasRole(par.PAUSER_ROLE(), HYPERNATIVE_PAUSER), true, 'HYPERNATIVE_PAUSER should have PAUSER_ROLE');
    assertEq(par.hasRole(par.PAUSER_ROLE(), TL_MULTISIG), true, 'TL_MULTISIG should have PAUSER_ROLE');
    assertEq(par.isPausable(), true, 'the contract should be pausable');
    assertEq(address(par.queue()) != address(0), true, 'queue should be set');
    assertEq(address(par.queue()), address(queue), 'queue address is correct');

    IParetoDollar.CollateralInfo memory usdcCollateral = par.getCollateralInfo(USDC);
    
    assertEq(par.collaterals(0), USDC, 'First collateral should be USDC');
    assertEq(usdcCollateral.allowed, true, 'USDC collateral should be allowed');
    assertEq(usdcCollateral.priceFeed, USDC_FEED, 'USDC priceFeed should be set');
    assertEq(usdcCollateral.tokenDecimals, 6, 'USDC should have 6 decimals');
    assertEq(usdcCollateral.priceFeedDecimals, USDT_FEED_DECIMALS, 'Price feed for USDC should have 8 decimals');
    assertEq(usdcCollateral.validityPeriod, 24 hours, 'Price feed for USDC should have validityPeriod of 24 hours');
  
    IParetoDollar.CollateralInfo memory usdtCollateral = par.getCollateralInfo(USDT);

    assertEq(par.collaterals(1), USDT, 'Second collateral should be USDT');
    assertEq(usdtCollateral.allowed, true, 'USDT collateral should be allowed');
    assertEq(usdtCollateral.priceFeed, USDT_FEED, 'USDT priceFeed should be set');
    assertEq(usdtCollateral.tokenDecimals, 6, 'USDT should have 6 decimals');
    assertEq(usdtCollateral.priceFeedDecimals, USDT_FEED_DECIMALS, 'Price feed for USDT should have 8 decimals');
    assertEq(usdtCollateral.validityPeriod, 24 hours, 'Price feed for USDT should have validityPeriod of 24 hours');

    address[] memory collaterals = par.getCollaterals();
    assertEq(collaterals.length, 3, 'There should be 2 collaterals');
    assertEq(collaterals[0], USDC, 'First collateral address in getCollaterals should be USDC');
    assertEq(collaterals[1], USDT, 'Second collateral address in getCollaterals should be USDT');
    assertEq(collaterals[2], USDS, 'Third collateral address in getCollaterals should be USDS');
  }

  function testAddCollateral() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.addCollateral(USDT, 6, address(1), 8, 1 hours);

    vm.startPrank(par.owner());
    // revert if token is address(0)
    vm.expectRevert(IParetoDollar.InvalidData.selector);
    par.addCollateral(address(0), 6, address(1), 8, 1 hours);
    
    // revert if priceFeed is address(0)
    vm.expectRevert(IParetoDollar.InvalidData.selector);
    par.addCollateral(USDT, 6, address(0), 8, 1 hours);

    vm.expectEmit(true, true, true, true);
    emit IParetoDollar.CollateralAdded(address(1), address(2), 6, 8, 1 hours);
    par.addCollateral(address(1), 6, address(2), 8, 1 hours);
    IParetoDollar.CollateralInfo memory newCollateral = par.getCollateralInfo(address(1));

    assertEq(newCollateral.allowed, true, 'new collateral should be allowed');
    assertEq(newCollateral.priceFeed, address(2), 'new priceFeed should be set');
    assertEq(newCollateral.tokenDecimals, 6, 'new should have 6 decimals');
    assertEq(newCollateral.priceFeedDecimals, 8, 'Price feed for USDT should have 8 decimals');
    assertEq(newCollateral.validityPeriod, 1 hours, 'Price feed for USDT should have validityPeriod of 1 hours');

    address[] memory collaterals = par.getCollaterals();
    assertEq(collaterals.length, 4, 'There should be 4 collaterals');
    assertEq(collaterals[3], address(1), 'New collateral address in getCollaterals should be address(1)');

    // overwrite collateral
    par.addCollateral(address(1), 66, address(22), 88, 2 hours);
    IParetoDollar.CollateralInfo memory newCollateral2 = par.getCollateralInfo(address(1));
    assertEq(newCollateral2.allowed, true, 'new collateral should be allowed');
    assertEq(newCollateral2.priceFeed, address(22), 'new priceFeed should be set');
    assertEq(newCollateral2.tokenDecimals, 66, 'new should have 6 decimals');
    assertEq(newCollateral2.priceFeedDecimals, 88, 'Price feed for USDT should have 8 decimals');
    assertEq(newCollateral2.validityPeriod, 2 hours, 'Price feed for USDT should have validityPeriod of 2 hours');
    assertEq(par.getCollaterals().length, 4, 'Collaterals length should not change');
    vm.stopPrank();
  }

  function testRemoveCollateral() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.removeCollateral(USDT);

    vm.startPrank(par.owner());
    vm.expectEmit(true, true, true,true);
    emit IParetoDollar.CollateralRemoved(USDC);
    par.removeCollateral(USDC);

    IParetoDollar.CollateralInfo memory usdcCollateral = par.getCollateralInfo(USDC);
    assertEq(usdcCollateral.allowed, false, 'USDC should not be allowed');
    assertEq(usdcCollateral.priceFeed, address(0), 'USDC feed should not be removed');
    assertEq(usdcCollateral.tokenDecimals, 0, 'USDC tokenDecimals should not be removed');
    assertEq(usdcCollateral.priceFeedDecimals, 0, 'USDC priceFeedDecimals should not be removed');
    assertEq(usdcCollateral.validityPeriod, 0, 'USDC validityPeriod should not be removed');

    vm.expectRevert(IParetoDollar.InvalidData.selector);
    par.removeCollateral(address(0));
    vm.stopPrank();

    address[] memory collaterals = par.getCollaterals();
    assertEq(collaterals.length, 2, 'There should be 1 collateral');
    assertEq(collaterals[0], USDS, 'First collateral address in getCollaterals should be USDS');
    assertEq(collaterals[1], USDT, 'Second collateral address in getCollaterals should be USDT');
  }

  function testSetKeyringParams() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.setKeyringParams(address(1), 1);

    vm.startPrank(par.owner());

    par.setKeyringParams(address(2), 2);

    assertEq(par.keyring(), address(2), 'keyring should be updated');
    assertEq(par.keyringPolicyId(), 2, 'keyring policy should be updated');
    
    vm.stopPrank();
  }

  function testEmergencyWithdraw() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.emergencyWithdraw(address(1), 1);

    deal(USDC, address(par), 100);

    uint256 balPre = IERC20Metadata(USDC).balanceOf(par.owner());

    vm.startPrank(par.owner());
    par.emergencyWithdraw(USDC, 100);
    uint256 balPost = IERC20Metadata(USDC).balanceOf(par.owner());
    assertEq(balPost, balPre + 100, 'owner balance should increase by 100');
    vm.stopPrank();
  }

  function testEmergencyBurn() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.emergencyBurn(1e18);

    address owner = par.owner();
    // allow anyone to mint
    vm.prank(owner);
    par.setKeyringParams(address(0), 1);

    vm.startPrank(owner);
    deal(USDC, owner, 1e6);
    IERC20Metadata(USDC).approve(address(par), 1e6);
    par.mint(USDC, 1e6);
    // burn
    par.emergencyBurn(1e18 / 2);
    vm.stopPrank();

    assertEq(par.totalSupply(), 1e18 / 2, 'totalSupply is wrong');
    assertEq(par.balanceOf(owner), 1e18 / 2, 'balanceOf owner is wrong after burn');
  }

  function testPause() external {
    vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), par.PAUSER_ROLE()));
    par.pause();

    vm.startPrank(par.owner());
    par.pause();
    assertEq(par.paused(), true, 'The contract should be paused');
    vm.stopPrank();

    // when paused no mints or redeems can be made
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    par.mint(USDC, 1e6);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    par.requestRedeem(1e18);
    vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
    par.claimRedeemRequest(1);
    vm.stopPrank();
  }

  function testUnpause() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.unpause();

    vm.startPrank(par.owner());
    par.pause();
    par.unpause();

    assertEq(par.paused(), false, 'The contract should not be paused');
    vm.stopPrank();
  }

  function testRoles() external {
    bytes32 pauser = par.PAUSER_ROLE();
    bytes32 defaultAdmin = par.DEFAULT_ADMIN_ROLE();

    bytes memory defaultError = abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), defaultAdmin);

    // if non admin tries to grant role, it reverts
    vm.expectRevert(defaultError);
    par.grantRole(pauser, address(this));
    vm.expectRevert(defaultError);
    par.grantRole(defaultAdmin, address(this));

    // if non admin tries to removke role, it reverts
    vm.expectRevert(defaultError);
    par.revokeRole(pauser, address(this));
    vm.expectRevert(defaultError);
    par.revokeRole(defaultAdmin, address(this));

    // admin can grant roles
    address admin = TL_MULTISIG;
    vm.startPrank(admin);
    par.grantRole(pauser, address(this));
    par.grantRole(defaultAdmin, address(this));
    assertEq(par.hasRole(pauser, address(this)), true, 'address(this) should have PAUSER_ROLE');
    assertEq(par.hasRole(defaultAdmin, address(this)), true, 'address(this) should have DEFAULT_ADMIN_ROLE');
    vm.stopPrank();

    // admin can revoke roles
    vm.startPrank(admin);
    par.revokeRole(pauser, address(this));
    par.revokeRole(defaultAdmin, address(this));
    assertEq(par.hasRole(pauser, address(this)), false, 'address(this) should not have PAUSER_ROLE');
    assertEq(par.hasRole(defaultAdmin, address(this)), false, 'address(this) should not have DEFAULT_ADMIN_ROLE');
    vm.stopPrank();
  }

  function testIsWalletAllowed() external {
    assertEq(par.isWalletAllowed(address(this)), false, 'This contract should not be allowed');

    address keyring = address(1);
    vm.prank(par.owner());
    par.setKeyringParams(keyring, 1);
    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );
    assertEq(par.isWalletAllowed(address(this)), true, 'This contract should be allowed');
    vm.clearMockedCalls();
  }

  function testGetOraclePrice() external {
    uint256 usdcPrice = par.getOraclePrice(USDC);
    assertGt(usdcPrice, 99 * 1e16, 'USDC price should be greater than 0.99');
    uint256 usdtPrice = par.getOraclePrice(USDT);
    assertGt(usdtPrice, 99 * 1e16, 'USDT price should be greater than 0.99');

    vm.expectRevert(IParetoDollar.CollateralNotAllowed.selector);
    par.getOraclePrice(address(1234));
  }

  function testOnlyKeyringUsersCanInteract() external {
    address keyring = address(1);

    vm.prank(par.owner());
    par.setKeyringParams(keyring, 1);

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(false)
    );

    vm.expectRevert(abi.encodeWithSelector(IParetoDollar.NotAllowed.selector));
    par.mint(USDC, 1);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollar.NotAllowed.selector));
    par.requestRedeem(1);
    vm.expectRevert(abi.encodeWithSelector(IParetoDollar.NotAllowed.selector));
    par.claimRedeemRequest(1);

    vm.clearMockedCalls();

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );

    deal(USDC, address(this), 100);
    IERC20Metadata(USDC).approve(address(par), 100);
    par.mint(USDC, 100);

    par.requestRedeem(100);
    vm.expectRevert(IParetoDollarQueue.NotReady.selector);
    par.claimRedeemRequest(1);

    vm.clearMockedCalls();
  }

  function testMint() external {
    // allow anyone to mint
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);

    // cannot mint with collateral not approved
    vm.expectRevert(IParetoDollar.CollateralNotAllowed.selector);
    par.mint(address(123), 1);

    deal(USDC, address(this), 1e6);
    IERC20Metadata(USDC).approve(address(par), 1e6);

    // cannot mint with collateral price too low
    vm.mockCall(
      address(USDC_FEED),
      abi.encodeWithSelector(IPriceFeed.latestRoundData.selector),
      abi.encode(uint80(1), int256(100), uint256(block.timestamp - 1), uint256(block.timestamp - 1), uint80(1))
    );
    vm.expectRevert(IParetoDollar.CollateralPriceBelowThreshold.selector);
    par.mint(USDC, 100);
    vm.clearMockedCalls();

    IParetoDollar.CollateralInfo memory usdcCollateral = par.getCollateralInfo(USDC);
    // cannot mint with stale price
    vm.mockCall(
      address(USDC_FEED),
      abi.encodeWithSelector(IPriceFeed.latestRoundData.selector),
      abi.encode(uint80(1), int256(1e8), uint256(block.timestamp - 1), uint256(block.timestamp - (usdcCollateral.validityPeriod + 1)), uint80(1))
    );
    vm.expectRevert(IParetoDollar.InvalidOraclePrice.selector);
    par.mint(USDC, 100);
    vm.clearMockedCalls();

    // can mint with stale price only if oracle validityPeriod is set to 0
    vm.startPrank(par.owner());
    par.addCollateral(
      USDC,
      IERC20Metadata(USDC).decimals(),
      USDC_FEED,
      USDC_FEED_DECIMALS,
      0 // set validity period to 0
    );
    vm.stopPrank();
    vm.mockCall(
      address(USDC_FEED),
      abi.encodeWithSelector(IPriceFeed.latestRoundData.selector),
      abi.encode(uint80(1), int256(1e8), uint256(block.timestamp - 1), uint256(block.timestamp - 25 hours), uint80(1))
    );
    uint256 mintedAmount = par.mint(USDC, 1e6);
    vm.clearMockedCalls();

    assertEq(IERC20Metadata(USDC).balanceOf(address(par)), 0, 'Par contract should not received collateral');
    assertEq(IERC20Metadata(USDC).balanceOf(address(queue)), 1e6, 'Queue contract should received collateral');
    assertEq(mintedAmount, 1e18, 'Should mint 1 USP token');
    assertEq(IERC20Metadata(USDC).balanceOf(address(this)), 0, 'Minter has no more balance');
    assertEq(IERC20Metadata(address(par)).balanceOf(address(this)), 1e18, 'Minter has 1 USP token');
  }

  function testRequestRedeem() external {
    // allow anyone to mint/redeem
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);

    uint256 amount = 1000 * 1e6;
    deal(USDC, address(this), amount);
    IERC20Metadata(USDC).approve(address(par), amount);
  
    par.mint(USDC, amount);

    uint256 uspAmount = 1000e18;
    // request redemption
    vm.expectEmit(true, true, true, true);
    emit IParetoDollar.RedeemRequested(address(this), queue.epochNumber(), uspAmount);
    par.requestRedeem(uspAmount);

    uint256 parBalPost = IERC20Metadata(address(par)).balanceOf(address(this));
    assertEq(parBalPost, 0, 'PAR balance should decrease by the redeemed amount');
    assertEq(queue.userWithdrawalsEpochs(address(this), 1), uspAmount, 'Queue requestCollateral is called');
  }

  function testClaimRequestRedeem() external {
    // allow anyone to mint/redeem
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);

    uint256 amount = 1000 * 1e6;
    deal(USDC, address(this), amount);
    IERC20Metadata(USDC).approve(address(par), amount);
  
    // mint 1000 USP
    par.mint(USDC, amount);
    // request redeem of 1000 USP
    uint256 uspAmount = 1000e18;
    par.requestRedeem(uspAmount);
    // claim redeem request for epoch 0. We check simply that the inner queue method is 
    // called and we do this by checking that it reverts with NotReady error
    vm.expectRevert(IParetoDollarQueue.NotReady.selector);
    par.claimRedeemRequest(1);

    // mockCall for queue.claimRequestedCollateral this is used to check that the return amount of
    // claimReedemRequest is the same return value as queue.claimRedeemRequest
    vm.mockCall(
      address(queue),
      abi.encodeWithSelector(IParetoDollarQueue.claimRedeemRequest.selector),
      abi.encode(uspAmount)
    );

    vm.expectEmit(true, true, true, true);
    emit IParetoDollar.Redeemed(address(this), 1, uspAmount);
    uint256 uspAmountRequested = par.claimRedeemRequest(1);
    assertEq(uspAmountRequested, uspAmount, 'Returned amount should be equal to requested USP amount');
  }

  function testMintForQueue() external {
    vm.expectRevert(IParetoDollar.NotAllowed.selector);
    par.mintForQueue(1234);

    vm.startPrank(address(queue));
    par.mintForQueue(1234);
    assertEq(IERC20Metadata(address(par)).balanceOf(address(queue)), 1234, 'Queue should have 1234 USP');
    vm.stopPrank();
  }
}