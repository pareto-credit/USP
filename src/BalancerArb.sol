// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;
//----------------------------------------------------------------------------------
// Interfaces
//----------------------------------------------------------------------------------

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
}

// Interface for the Pareto USP contract
interface IParetoDollar {
  function mint(address collateralToken, uint256 amount) external;
}

// Interface for the Balancer Vault's flash loan callback
interface IFlashLoanRecipient {
  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external;
}

// Interface for the Balancer Vault
interface IBalancerVault {
  function flashLoan(
    IFlashLoanRecipient recipient,
    IERC20[] memory tokens,
    uint256[] memory amounts,
    bytes memory userData
  ) external;
}

// Interface for the Balancer V3 Router
interface IBalancerV3Router {
  function swapSingleTokenExactIn(
    address pool,
    IERC20 tokenIn,
    IERC20 tokenOut,
    uint256 exactAmountIn,
    uint256 minAmountOut,
    uint256 deadline,
    bool wethIsEth,
    bytes calldata userData
  ) external payable returns (uint256 amountOut);
}

interface IBalancerPool {
  function getCurrentLiveBalances() external view returns (uint256[] memory amounts);
}

// Interface for ERC4626 Vaults
interface IERC4626 is IERC20 {
  function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
  function convertToAssets(uint256 shares) external view returns (uint256 assets);
}

interface IPermit2 {
  function approve(
    address token,
    address spender,
    uint160 amount,
    uint48 expiration
  ) external;
}

//----------------------------------------------------------------------------------
// Arbitrage Contract
//----------------------------------------------------------------------------------

/**
 * @title BalancerArb
 * @author Bugduino + Gemini
 * @notice Performs arbitrage by taking a Balancer V3 flash loan, minting USP,
 * selling the USP for waEthUSDC, unwrapping it to USDC via ERC4626 redeem, 
 * repaying the loan, and banking the profit.
 */
contract BalancerArb is IFlashLoanRecipient {
  //------------------------------------------------------------------------------
  // Hardcoded Addresses & Constants
  //------------------------------------------------------------------------------

  // Balancer V2 Contracts used for flash loan
  IBalancerVault private constant BALANCER_VAULT = IBalancerVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
  // Balancer V3 1-Step Router
  IBalancerV3Router private constant BALANCER_ROUTER = IBalancerV3Router(0xAE563E3f8219521950555F5962419C8919758Ea2);
  // Uniswap Permit2 Contract
  // The Balancer V3 Router uses Permit2 for token approvals. We must approve this contract.
  IPermit2 private constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

  // Token & Application Contracts
  IERC20 private constant USP = IERC20(0x97cCC1C046d067ab945d3CF3CC6920D3b1E54c88);
  IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  IParetoDollar private constant USP_MINTER = IParetoDollar(address(USP));
  
  // ERC4626 Vault Token
  IERC4626 private constant WAETHUSDC = IERC4626(0xD4fa2D31b7968E448877f69A96DE69f5de8cD23E);
  // Beneficiary for profits
  address private constant BENEFICIARY = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  // The address of the Balancer pool
  address private constant POOL_ADDRESS = 0x114907c2a07978c38EbB9F9F6A5261a846B79521;
  // The address of the rebalancer 
  address private constant REBALANCER = 0xB3C8e5534F0063545CBbb7Ce86854Bf42dB8872B;

  // Contract owner
  address public immutable owner;

  //------------------------------------------------------------------------------
  // Constructor
  //------------------------------------------------------------------------------

  constructor() {
    owner = msg.sender;

    USDC.approve(address(USP_MINTER), type(uint256).max);
    // We must approve the Permit2 contract, which the Balancer Router uses for token transfers.
    USP.approve(address(PERMIT2), type(uint256).max);
    PERMIT2.approve(address(USP), address(BALANCER_ROUTER), uint160(type(uint256).max), uint48(type(uint256).max));
  }

  //------------------------------------------------------------------------------
  // External Functions
  //------------------------------------------------------------------------------

  /**
   * @notice Starts the arbitrage process.
   */
  function arb(uint256 uspAmountToSell) external {
    require(msg.sender == owner || msg.sender == REBALANCER, "Caller is not allowed");

    if (uspAmountToSell == 0) {
      uspAmountToSell = _calculateUSPAmountToSell();
    }
    require(uspAmountToSell > 0, "USP amount to sell must be greater than 0");
  
    IERC20[] memory tokens = new IERC20[](1);
    tokens[0] = USDC;

    uint256[] memory amounts = new uint256[](1);
    // Convert USP amount (18 decimals) to USDC amount (6 decimals) for the loan
    amounts[0] = uspAmountToSell / 1e12; 

    BALANCER_VAULT.flashLoan(this, tokens, amounts, "");
  }

  /**
   * @notice The callback function that the Balancer Vault calls after providing the loan.
   */
  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory
  ) external override {
    // --- Security Checks ---
    require(msg.sender == address(BALANCER_VAULT), "Caller is not the Balancer Vault");
    require(tokens.length == 1 && address(tokens[0]) == address(USDC), "Invalid flash loan token");

    // --- Arbitrage Logic ---
    uint256 usdcLoanAmount = amounts[0];

    // 1. Mint USP with the borrowed USDC
    uint256 uspBalanceBefore = USP.balanceOf(address(this));
    USP_MINTER.mint(address(USDC), usdcLoanAmount);
    uint256 uspBalanceAfter = USP.balanceOf(address(this));
    uint256 mintedUspAmount = uspBalanceAfter - uspBalanceBefore;

    // 2. Sell the minted USP for waEthUSDC via the Balancer V3 Router

    BALANCER_ROUTER.swapSingleTokenExactIn(
      POOL_ADDRESS,
      USP,
      IERC20(address(WAETHUSDC)), 
      mintedUspAmount,
      0, // minAmountOut
      block.timestamp, // deadline
      false, // wethIsEth
      "" // userData for swap, not used
    );
    
    // 3. Redeem waEthUSDC for USDC using ERC4626
    WAETHUSDC.redeem(WAETHUSDC.balanceOf(address(this)), address(this), address(this));

    // 4. Repay the Balancer Flash Loan and Transfer Profit
    uint256 usdcBalanceAfterRedeem = USDC.balanceOf(address(this));
    uint256 totalDebt = usdcLoanAmount + feeAmounts[0];

    require(usdcBalanceAfterRedeem > totalDebt, "Arbitrage loss");

    // Transfer profit to the beneficiary
    USDC.transfer(BENEFICIARY, usdcBalanceAfterRedeem - totalDebt);
    // Repay the flash loan
    USDC.transfer(address(BALANCER_VAULT), totalDebt);
  }

  //------------------------------------------------------------------------------
  // Helper Functions
  //------------------------------------------------------------------------------

  /**
   * @notice Calculates the amount of USP to sell based on the current market conditions.
   * The pool is balanced when there is an equal amount of USDC and waEthUSDC (in USD) in the balancer pool.
   * If the amount is eg 40% USP and 60% waEthUSDC, we sell need to convert 10% of waEthUSDC to USP.
   * NOTE: this won't maximize profit instead maximizes the amount of USP mint and sold to the pool.
   */
  function _calculateUSPAmountToSell() internal view returns (uint256 _value) {
    (uint256[] memory balances) = IBalancerPool(POOL_ADDRESS).getCurrentLiveBalances();
    uint256 uspBalance = balances[0]; // USP balance in the pool
    uint256 waEthUsdcBalance = balances[1]; // waEthUSDC balance in USDC scaled to 18 decimals
    if (uspBalance < waEthUsdcBalance) {
      _value = (uspBalance + waEthUsdcBalance) / 2 - uspBalance;
    }
  }

  /**
   * @notice Allows the owner to withdraw any tokens accidentally sent to this contract.
   */
  function withdrawStuckTokens(address tokenAddress) external {
    require(msg.sender == owner, "Caller is not the owner");
    IERC20 token = IERC20(tokenAddress);
    token.transfer(owner, token.balanceOf(address(this)));
  }
}
