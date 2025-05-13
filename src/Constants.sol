// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract Constants {
  // MAINNET
  address public constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  // Keyring whitelist contract and policy id
  address public constant KEYRING_WHITELIST = 0x6351370a1c982780Da2D8c85DfedD421F7193Fa5;
  uint256 public constant KEYRING_POLICY = 11054401;
  // Hypernative pauser multisig
  address public constant HYPERNATIVE_PAUSER = 0xBaeCba470C229984b75BC860EFe8e97AE082Bb9f;
  // USDC feed data
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address public constant USDC_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
  // USDT feed data
  address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address public constant USDT_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
  // USDS feed data
  address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
  address public constant USDS_FEED = 0xfF30586cD0F29eD462364C7e81375FC0C71219b1;
  // Fas USDC credit vault
  address public constant FAS_USDC_CV = 0xf6223C567F21E33e859ED7A045773526E9E3c2D5;
  address public constant AA_FAS_USDC_CV = 0x45054c6753b4Bce40C5d54418DabC20b070F85bE;
  // Bastion USDC credit vault
  address public constant BAS_USDC_CV = 0x4462eD748B8F7985A4aC6b538Dfc105Fce2dD165;
  address public constant AA_BAS_USDC_CV = 0xC49b4ECc14aa31Ef0AD077EdcF53faB4201b724c;
  // sUSDS ERC4626 vault
  address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
  address public constant USDS_USDC_PSM = 0xA188EEC8F81263234dA3622A406892F3D630f98c;

  // METHODS SIGNATURES
  // Credit vaults methods sig
  // bytes4(keccak256(bytes("depositAA(uint256)")))
  bytes4 public constant DEPOSIT_AA_SIG = 0xb450dfce;
  // bytes4(keccak256(bytes("requestWithdraw(uint256,address)")))
  bytes4 public constant WITHDRAW_AA_SIG = 0xccc143b8;
  // bytes4(keccak256(bytes("claimWithdrawRequest()")))
  bytes4 public constant CLAIM_REQ_SIG = 0x33986ffa;
  // bytes4(keccak256(bytes("claimInstantWithdrawRequest()")))
  bytes4 public constant CLAIM_INSTANT_REQ_SIG = 0x991052b7;
  // ERC4626 vaults methods sig
  // bytes4(keccak256(bytes("deposit(uint256,address)")))
  bytes4 public constant DEPOSIT_4626_SIG = 0x6e553f65;
  // bytes4(keccak256(bytes("withdraw(uint256,address,address)")))
  bytes4 public constant WITHDRAW_4626_SIG = 0xb460af94;
  // bytes4(keccak256(bytes("redeem(uint256,address,address)")))
  bytes4 public constant REDEEM_4626_SIG = 0xba087652;
  // USDS-USDC PSM methods sig
  // bytes4(keccak256(bytes("buyGem(address,uint256)")))
  bytes4 public constant BUY_GEM_SIG = 0x8d7ef9bb;
  // bytes4(keccak256(bytes("sellGem(address,uint256)")))
  bytes4 public constant SELL_GEM_SIG = 0x95991276;
}