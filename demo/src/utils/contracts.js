import { ethers } from 'ethers'

export const CONTRACT_ADDRESSES = {
  ACTX_TOKEN_PROXY: '0x393F332Da314C411cD4B577e3aD433a7DeB54b4b',
  ACTX_AIRDROP: '0xF4Cd6296076f904A22e6D99d0AFfaFC31d1276e3',
  ACTX_VESTING: '0x095Da4d3fBF1B449Da3504a5CfCCD54219bbF81a'
}

export const SEPOLIA_CHAIN_ID = 11155111

export const ACTX_TOKEN_ABI = [
  "function name() view returns (string)",
  "function symbol() view returns (string)",
  "function decimals() view returns (uint8)",
  "function totalSupply() view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
  "function transfer(address to, uint256 amount) returns (bool)",
  "function distributeReward(address recipient, uint256 amount)",
  "function batchDistributeRewards(address[] recipients, uint256[] amounts)",
  "function rewardPoolBalance() view returns (uint256)",
  "function totalRewardsDistributed() view returns (uint256)",
  "function taxRateBasisPoints() view returns (uint256)",
  "function reservoirAddress() view returns (address)",
  "function treasuryAddress() view returns (address)",
  "function isTaxExempt(address) view returns (bool)",
  "function version() view returns (uint256)",
  "function getTokenStats() view returns (uint256, uint256, uint256, uint256, uint256, uint256)",
  "function calculateTax(uint256) view returns (uint256, uint256)",
  "function hasRole(bytes32, address) view returns (bool)",
  "function pause()",
  "function unpause()",
  "function paused() view returns (bool)",
  "event RewardDistributed(address indexed recipient, uint256 amount, uint256 rewardPoolRemaining, uint256 timestamp)",
  "event TaxCollected(address indexed from, address indexed to, uint256 taxAmount, uint256 netAmount)",
  "event LeaderboardAction(address indexed user, string action, uint256 amount, bytes metadata)",
  "event TaxRateUpdated(uint256 oldRate, uint256 newRate)",
  "event Transfer(address indexed from, address indexed to, uint256 value)"
]

export const ROLES = {
  DEFAULT_ADMIN_ROLE: '0x0000000000000000000000000000000000000000000000000000000000000000',
  REWARD_MANAGER_ROLE: ethers.keccak256(ethers.toUtf8Bytes('REWARD_MANAGER_ROLE')),
  TAX_MANAGER_ROLE: ethers.keccak256(ethers.toUtf8Bytes('TAX_MANAGER_ROLE')),
  PAUSER_ROLE: ethers.keccak256(ethers.toUtf8Bytes('PAUSER_ROLE')),
  UPGRADER_ROLE: ethers.keccak256(ethers.toUtf8Bytes('UPGRADER_ROLE'))
}

export function getProvider() {
  if (typeof window !== 'undefined' && window.ethereum) {
    return new ethers.BrowserProvider(window.ethereum)
  }
  return new ethers.JsonRpcProvider('https://sepolia.infura.io/v3/9aa3d95b3bc440fa88ea12eaa4456161')
}

export function formatTokenAmount(amount, decimals = 18) {
  if (amount === null || amount === undefined) {
    return '0'
  }
  try {
    return ethers.formatUnits(amount, decimals)
  } catch (err) {
    console.warn('Error formatting token amount:', err, amount)
    return '0'
  }
}

export function parseTokenAmount(amount, decimals = 18) {
  return ethers.parseUnits(amount.toString(), decimals)
}

export function shortenAddress(address) {
  if (!address) return ''
  return `${address.slice(0, 6)}...${address.slice(-4)}`
}

