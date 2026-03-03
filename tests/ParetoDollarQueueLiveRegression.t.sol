// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/Test.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { ParetoDollarQueue } from "../src/ParetoDollarQueue.sol";
import { IIdleCDOEpochVariant } from "../src/interfaces/IIdleCDOEpochVariant.sol";
import { IIdleCreditVault } from "../src/interfaces/IIdleCreditVault.sol";
import { Constants } from "../src/Constants.sol";
import { Addresses } from "../src/Addresses.sol";

contract TestParetoDollarQueueLiveRegression is Test, Constants, Addresses {
  using SafeERC20 for IERC20Metadata;

  // keccak256("eip1967.proxy.implementation") - 1
  bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894A13BA1A3210667C828492DB98DCA3E2076CC3735A920A3CA505D382BBC;
  uint256 internal constant EPOCH_INTEREST_OVERRIDE = 10_000e6; // 10k USDC (6 decimals)
  uint256 internal constant TRANCHE_REDEEM_TO_TRIGGER_SETTLE = 1e18; // 1 AA tranche token

  function setUp() public {
    vm.createSelectFork("mainnet", 24_570_746);
    vm.label(QUEUE, "Queue");
    vm.label(USP, "USP");
    vm.label(FAS_USDC_CV, "FAS_USDC_CV");
  }

  function testFasanaraApr0PendingRequestsAreCountedAfterQueueUpgrade() external {
    IIdleCDOEpochVariant cv = IIdleCDOEpochVariant(FAS_USDC_CV);
    IIdleCreditVault strategy = IIdleCreditVault(cv.strategy());

    // This is the exact on-chain issue:
    // request exists, but not in withdrawsRequests(queue).
    assertEq(strategy.withdrawsRequests(QUEUE), 0, "unexpected withdrawsRequests value");
    assertEq(strategy.instantWithdrawsRequests(QUEUE), 0, "unexpected instantWithdrawsRequests value");
    (uint256 principal,,,) = strategy.apr0Users(QUEUE);
    assertGt(principal, 0, "apr0Users principal should be > 0");

    // Pre-upgrade live queue is undercollateralized due missing APR0 accounting.
    assertFalse(ParetoDollarQueue(QUEUE).isParetoDollarCollateralized(), "pre-upgrade queue should be undercollateralized");

    // Upgrade queue proxy implementation in-fork to local code under test.
    _upgradeQueueProxyToCurrentImplementation();

    // After fix, APR0 pending request should be included in collateralization checks.
    assertTrue(ParetoDollarQueue(QUEUE).isParetoDollarCollateralized(), "apr0 pending should be counted");
  }

  function testFasanaraApr0SettledAmountsAreCountedAfterQueueUpgrade() external {
    IIdleCDOEpochVariant cv = IIdleCDOEpochVariant(FAS_USDC_CV);
    IIdleCreditVault strategy = IIdleCreditVault(cv.strategy());

    (uint256 principalBefore,,uint256 settledPrincipalBefore,uint256 settledInterestBefore) = strategy.apr0Users(QUEUE);
    assertGt(principalBefore, 0, "expected apr0 principal on live fork");
    assertEq(settledPrincipalBefore, 0, "expected settledPrincipal to be zero at this block");
    assertEq(settledInterestBefore, 0, "expected settledInterest to be zero at this block");

    // Real flow to settle APR0:
    // 1. roll one full CV epoch with non-zero override interest to set apr0RateByEpoch
    // 2. do another real withdraw request so strategy._settleApr0(queue) moves amounts to settled fields
    _rollEpochCV(FAS_USDC_CV, EPOCH_INTEREST_OVERRIDE);
    _requestRedeemCV(FAS_USDC_CV, TRANCHE_REDEEM_TO_TRIGGER_SETTLE);

    (uint256 principalAfter,,uint256 settledPrincipalAfter,uint256 settledInterestAfter) = strategy.apr0Users(QUEUE);
    assertGt(principalAfter, 0, "new apr0 principal should be open after the second request");
    assertGt(settledPrincipalAfter, 0, "settledPrincipal should be populated by _settleApr0");
    assertGt(settledInterestAfter, 0, "settledInterest should be populated by _settleApr0");

    // Pre-upgrade queue still ignores all APR0 accounting.
    assertFalse(ParetoDollarQueue(QUEUE).isParetoDollarCollateralized(), "pre-upgrade should still be undercollateralized");

    _upgradeQueueProxyToCurrentImplementation();

    ParetoDollarQueue queue = ParetoDollarQueue(QUEUE);
    uint256 settledScaled = (settledPrincipalAfter + settledInterestAfter) * 1e12;
    uint256 totalWithSettled = queue.getTotalCollateralsScaled();
    uint256 parSupply = IERC20Metadata(USP).totalSupply() + queue.totReservedWithdrawals();

    // Demonstrate why settled fields are needed: removing them would make the system undercollateralized.
    assertLt(
      totalWithSettled - settledScaled + queue.THRESHOLD(),
      parSupply,
      "without settledPrincipal+settledInterest system would be undercollateralized"
    );
    assertTrue(queue.isParetoDollarCollateralized(), "settledPrincipal+settledInterest should be counted");
  }

  function testFasanaraApr0ClaimKeepsAccountingHealthyAfterQueueUpgrade() external {
    IIdleCDOEpochVariant cv = IIdleCDOEpochVariant(FAS_USDC_CV);
    IIdleCreditVault strategy = IIdleCreditVault(cv.strategy());
    ParetoDollarQueue queue = ParetoDollarQueue(QUEUE);
    IERC20Metadata token = IERC20Metadata(cv.token());

    uint256 pendingBeforeUpgrade = _creditVaultPendingLikeQueue(strategy);
    assertGt(pendingBeforeUpgrade, 0, "expected live pending credit vault withdrawals");
    assertFalse(queue.isParetoDollarCollateralized(), "pre-upgrade queue should be undercollateralized");

    _upgradeQueueProxyToCurrentImplementation();
    assertTrue(queue.isParetoDollarCollateralized(), "post-upgrade queue should be collateralized");

    // Process one full CV epoch so pending requests are claimable.
    _rollEpochCV(FAS_USDC_CV, EPOCH_INTEREST_OVERRIDE);

    uint256 totalBeforeClaim = queue.getTotalCollateralsScaled();
    uint256 pendingBeforeClaim = _creditVaultPendingLikeQueue(strategy);
    uint256 queueBalBeforeClaim = token.balanceOf(QUEUE);

    _claimRedeemRequestCV(FAS_USDC_CV, queue.epochNumber());

    uint256 totalAfterClaim = queue.getTotalCollateralsScaled();
    uint256 pendingAfterClaim = _creditVaultPendingLikeQueue(strategy);
    uint256 queueBalAfterClaim = token.balanceOf(QUEUE);

    assertGt(queueBalAfterClaim, queueBalBeforeClaim, "queue should receive claimed underlying");
    assertLt(pendingAfterClaim, pendingBeforeClaim, "pending should decrease after claim");

    // Accounting invariant around claim:
    // total collaterals delta = queue underlying balance delta - pending requests delta (both scaled to 18 decimals).
    uint256 queueDeltaScaled = (queueBalAfterClaim - queueBalBeforeClaim) * 1e12;
    uint256 pendingDeltaScaled = (pendingBeforeClaim - pendingAfterClaim) * 1e12;
    uint256 expectedTotalAfterClaim = totalBeforeClaim + queueDeltaScaled - pendingDeltaScaled;
    assertApproxEqAbs(totalAfterClaim, expectedTotalAfterClaim, queue.THRESHOLD(), "claim should keep collateral accounting coherent");
    assertTrue(queue.isParetoDollarCollateralized(), "queue should remain collateralized after claim");
  }

  function _upgradeQueueProxyToCurrentImplementation() internal {
    ParetoDollarQueue impl = new ParetoDollarQueue();
    vm.store(QUEUE, IMPLEMENTATION_SLOT, bytes32(uint256(uint160(address(impl)))));
  }

  function _requestRedeemCV(address source, uint256 trancheAmount) internal {
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = WITHDRAW_AA_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode(trancheAmount, IIdleCDOEpochVariant(source).AATranche());
    vm.prank(TL_MULTISIG);
    ParetoDollarQueue(QUEUE).callWhitelistedMethods(sources, methods, args);
  }

  function _claimRedeemRequestCV(address source, uint256 epoch) internal {
    address[] memory sources = new address[](1);
    sources[0] = source;
    bytes4[] memory methods = new bytes4[](1);
    methods[0] = CLAIM_REQ_SIG;
    bytes[] memory args = new bytes[](1);
    args[0] = abi.encode();
    vm.prank(TL_MULTISIG);
    ParetoDollarQueue(QUEUE).redeemFunds(sources, methods, args, epoch);
  }

  function _rollEpochCV(address source, uint256 interestOverride) internal {
    IIdleCDOEpochVariant vault = IIdleCDOEpochVariant(source);
    IIdleCreditVault strategy = IIdleCreditVault(vault.strategy());
    address manager = strategy.manager();
    address borrower = strategy.borrower();
    address token = vault.token();
    uint256 unscaledApr = strategy.unscaledApr();

    if (vault.epochEndDate() != 0) {
      vm.warp(block.timestamp + vault.bufferPeriod() + 1);
    }
    vm.prank(manager);
    vault.startEpoch();

    uint256 expectedFunds = (interestOverride > 1 ? interestOverride : vault.expectedEpochInterest()) + strategy.pendingWithdraws();
    deal(token, borrower, expectedFunds);
    vm.startPrank(borrower);
    IERC20Metadata(token).safeIncreaseAllowance(source, expectedFunds);
    vm.stopPrank();

    vm.warp(vault.epochEndDate() + 1);
    vm.prank(manager);
    vault.stopEpoch(unscaledApr, interestOverride);
  }

  function _creditVaultPendingLikeQueue(IIdleCreditVault strategy) internal view returns (uint256 pending) {
    pending = strategy.withdrawsRequests(QUEUE) + strategy.instantWithdrawsRequests(QUEUE);
    (uint256 principal,,uint256 settledPrincipal,uint256 settledInterest) = strategy.apr0Users(QUEUE);
    pending += principal + settledPrincipal + settledInterest;
  }
}
