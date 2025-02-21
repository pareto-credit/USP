// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Test } from "forge-std/Test.sol";
import { console2 } from "forge-std/console2.sol";

import { ParetoDollar } from "../src/ParetoDollar.sol";
import { IParetoDollar } from "../src/interfaces/IParetoDollar.sol";
import { IPriceFeed } from "../src/interfaces/IPriceFeed.sol";
import { IKeyring } from "../src/interfaces/IKeyring.sol";
import { DeployScript, Constants } from "../script/Deploy.s.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


contract TestParetoDollar is Test, DeployScript {
  using SafeERC20 for IERC20Metadata;
  ParetoDollar par;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par) = _deploy(false);
    vm.stopPrank();

    skip(100);
  }

  function testInitialize() external view {
    assertEq(par.name(), 'Pareto synthetic dollar USP', 'name is wrong');
    assertEq(par.symbol(), 'USP', 'symbol is wrong');
    assertEq(par.owner(), DEPLOYER, 'owner is wrong');

    assertEq(par.totalSupply(), 0, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');

    assertEq(par.keyring(), KEYRING_WHITELIST, 'keyring is wrong');
    assertEq(par.keyringPolicyId(), KEYRING_POLICY, 'keyring policy is wrong');

    IParetoDollar.CollateralInfo memory usdcCollateral = par.getCollateralInfo(USDC);
    
    assertEq(usdcCollateral.allowed, true, 'USDC collateral should be allowed');
    assertEq(usdcCollateral.priceFeed, USDC_FEED, 'USDC priceFeed should be set');
    assertEq(usdcCollateral.fallbackPriceFeed, USDC_FALLBACK_FEED, 'USDC fallbackPriceFeed should be set');
    assertEq(usdcCollateral.tokenDecimals, 6, 'USDC should have 6 decimals');
    assertEq(usdcCollateral.priceFeedDecimals, USDT_FEED_DECIMALS, 'Price feed for USDC should have 8 decimals');
    assertEq(usdcCollateral.fallbackPriceFeedDecimals, USDT_FALLBACK_FEED_DECIMALS, 'Fallback price feed for USDC should have 8 decimals');
  
    IParetoDollar.CollateralInfo memory usdtCollateral = par.getCollateralInfo(USDT);

    assertEq(usdtCollateral.allowed, true, 'USDT collateral should be allowed');
    assertEq(usdtCollateral.priceFeed, USDT_FEED, 'USDT priceFeed should be set');
    assertEq(usdtCollateral.fallbackPriceFeed, USDT_FALLBACK_FEED, 'USDT fallbackPriceFeed should be set');
    assertEq(usdtCollateral.tokenDecimals, 6, 'USDT should have 6 decimals');
    assertEq(usdtCollateral.priceFeedDecimals, USDT_FEED_DECIMALS, 'Price feed for USDT should have 8 decimals');
    assertEq(usdtCollateral.fallbackPriceFeedDecimals, USDT_FALLBACK_FEED_DECIMALS, 'Fallback price feed for USDT should have 8 decimals');
  }

  function testAddCollateral() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.addCollateral(USDT, 6, address(1), 8, address(1), 8);

    vm.startPrank(par.owner());
    // revert if token is address(0)
    vm.expectRevert(IParetoDollar.InvalidData.selector);
    par.addCollateral(address(0), 6, address(1), 8, address(1), 8);
    
    // revert if priceFeed is address(0)
    vm.expectRevert(IParetoDollar.InvalidData.selector);
    par.addCollateral(USDT, 6, address(0), 8, address(1), 8);


    par.addCollateral(address(1), 6, address(2), 8, address(3), 10);
    IParetoDollar.CollateralInfo memory newCollateral = par.getCollateralInfo(address(1));

    assertEq(newCollateral.allowed, true, 'new collateral should be allowed');
    assertEq(newCollateral.priceFeed, address(2), 'new priceFeed should be set');
    assertEq(newCollateral.fallbackPriceFeed, address(3), 'new fallbackPriceFeed should be set');
    assertEq(newCollateral.tokenDecimals, 6, 'new should have 6 decimals');
    assertEq(newCollateral.priceFeedDecimals, 8, 'Price feed for USDT should have 8 decimals');
    assertEq(newCollateral.fallbackPriceFeedDecimals, 10, 'Fallback price feed for USDT should have 8 decimals');
    vm.stopPrank();
  }

  function testRemoveCollateral() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.removeCollateral(USDT);

    vm.startPrank(par.owner());
    par.removeCollateral(USDC);

    IParetoDollar.CollateralInfo memory usdcCollateral = par.getCollateralInfo(USDC);
    assertEq(usdcCollateral.allowed, false, 'USDC should not be allowed');
    assertEq(usdcCollateral.priceFeed, USDC_FEED, 'USDC feed should not be removed');

    vm.expectRevert(IParetoDollar.InvalidData.selector);
    par.removeCollateral(address(0));
    vm.stopPrank();
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

    uint256 balPre = IERC20Metadata(USDC).balanceOf(DEPLOYER);

    vm.startPrank(par.owner());
    par.emergencyWithdraw(USDC, 100);
    uint256 balPost = IERC20Metadata(USDC).balanceOf(DEPLOYER);
    assertEq(balPost, balPre + 100, 'DEPLOYER balance should increase by 100');
    vm.stopPrank();
  }

  function testPause() external {
    vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(this)));
    par.pause();

    vm.startPrank(par.owner());
    par.pause();
    assertEq(par.paused(), true, 'The contract should be paused');
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
    par.redeem(USDC, 1);

    vm.clearMockedCalls();

    vm.mockCall(
      keyring,
      abi.encodeWithSelector(IKeyring.checkCredential.selector),
      abi.encode(true)
    );

    deal(USDC, address(this), 100);
    IERC20Metadata(USDC).approve(address(par), 100);
    par.mint(USDC, 100);

    par.redeem(USDC, 100);
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

    par.mint(USDC, 1e6);

    assertEq(IERC20Metadata(USDC).balanceOf(address(this)), 0, 'Minter has no more balance');
    assertEq(IERC20Metadata(address(par)).balanceOf(address(this)), 1e18, 'Minter has 1 USP token');
  }

  function testRedeem() external {
    // allow anyone to mint/redeem
    vm.prank(par.owner());
    par.setKeyringParams(address(0), 1);

    uint256 amount = 1000 * 1e6;
    deal(USDC, address(this), amount);
    IERC20Metadata(USDC).approve(address(par), amount);
  
    par.mint(USDC, amount);

    vm.expectRevert(IParetoDollar.CollateralNotAllowed.selector);
    par.redeem(address(123), 1);

    uint256 redeemAmount = amount * 10**12;
    // transfer out of the contract amount - 1;
    vm.prank(par.owner());
    par.emergencyWithdraw(USDC, amount);
    vm.expectRevert(IParetoDollar.InsufficientCollateral.selector);
    par.redeem(USDC, redeemAmount);

    // return the collateral to the contract
    vm.prank(par.owner());
    IERC20Metadata(USDC).transfer(address(par), amount);

    uint256 usdcBalPre = IERC20Metadata(USDC).balanceOf(address(this));

    par.redeem(USDC, redeemAmount);

    uint256 parBalPost = IERC20Metadata(address(par)).balanceOf(address(this));
    uint256 usdcBalPost = IERC20Metadata(USDC).balanceOf(address(this));

    assertEq(parBalPost, 0, 'PAR balance should decrease by the redeemed amount');
    assertEq(usdcBalPost, usdcBalPre + amount, 'USDC balance should increase by the redeemed amount');
  }

  // TODO add return values for mint and redeem
}