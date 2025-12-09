# ACT.X Token

ERC-20 rewards token for BlessUP's referral economy. Built with UUPS upgradeable architecture, role-based access control, and transaction tax mechanism.

## Deployed Contracts (Sepolia)

| Contract | Address |
|----------|---------|
| ACTXToken (Proxy) | [`0x393F332Da314C411cD4B577e3aD433a7DeB54b4b`](https://sepolia.etherscan.io/address/0x393F332Da314C411cD4B577e3aD433a7DeB54b4b) |
| ACTXToken (Implementation) | [`0xccfB55028b03Cb59AEFd9C609FD9BD404449ca97`](https://sepolia.etherscan.io/address/0xccfB55028b03Cb59AEFd9C609FD9BD404449ca97) |
| ACTXAirdrop | [`0xF4Cd6296076f904A22e6D99d0AFfaFC31d1276e3`](https://sepolia.etherscan.io/address/0xF4Cd6296076f904A22e6D99d0AFfaFC31d1276e3) |
| ACTXVesting | [`0x095Da4d3fBF1B449Da3504a5CfCCD54219bbF81a`](https://sepolia.etherscan.io/address/0x095Da4d3fBF1B449Da3504a5CfCCD54219bbF81a) |

## Architecture

### System Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   BlessUP App   │────>│  Backend API    │────>│    RPC Node     │
│   (Frontend)    │     │  (Validation)   │     │    (Base L2)    │
└─────────────────┘     └────────┬────────┘     └────────┬────────┘
                                 │                       │
                                 │  distributeReward()   │
                                 └───────────────────────┘
                                             │
                    ┌────────────────────────┼────────────────────────┐
                    │                        │                        │
            ┌───────▼───────┐       ┌───────▼───────┐       ┌───────▼───────┐
            │  ACTXToken    │       │   Airdrop     │       │   Vesting     │
            │  (Proxy)      │       │   (Merkle)    │       │   (Linear)    │
            └───────────────┘       └───────────────┘       └───────────────┘
```

### Contract Architecture

**ACTXToken** uses UUPS proxy pattern for upgradeability:

```
ERC1967Proxy (Storage)
    │
    └──> ACTXToken Implementation
            ├── ERC20Upgradeable
            ├── AccessControlUpgradeable (5 roles)
            ├── PausableUpgradeable
            ├── ReentrancyGuardUpgradeable
            └── UUPSUpgradeable
```

### Data Flow

1. User completes 15-min time-bank requirement in BlessUP app
2. Backend validates action and calls `distributeReward(recipient, amount)`
3. Contract verifies caller has `REWARD_MANAGER_ROLE`
4. Tokens transferred from treasury to recipient (tax-exempt)
5. `RewardDistributed` event emitted for off-chain tracking

### Tokenomics

- **Total Supply:** 100,000,000 ACTX (fixed at deployment)
- **Tax Rate:** 2% on transfers (configurable 0-10%)
- **Reward Pool:** 10,000,000 ACTX allocated for distribution

## Contracts

### ACTXToken.sol

Core ERC-20 with UUPS upgradeability and transaction tax.

| Role | Purpose |
|------|---------|
| DEFAULT_ADMIN_ROLE | Grant/revoke roles, manage treasury |
| REWARD_MANAGER_ROLE | Distribute rewards from pool |
| TAX_MANAGER_ROLE | Adjust tax rate and exemptions |
| PAUSER_ROLE | Emergency pause |
| UPGRADER_ROLE | Authorize upgrades |

Key functions:
```solidity
function distributeReward(address recipient, uint256 amount) external;
function batchDistributeRewards(address[] recipients, uint256[] amounts) external;
function setTaxRate(uint256 newTaxRateBP) external;
function setTaxExemption(address account, bool exempt) external;
```

### Airdrop.sol

Merkle-tree based distribution with KYC gating option.

- Multiple campaign support
- Time-bounded claims
- Unclaimed token recovery

### Vesting.sol

Linear vesting for team/advisors.

- 4-year vesting, 1-year cliff (default)
- Revocable schedules
- Batch creation

## Security Testing

### Test Coverage

| Type | Count | Purpose |
|------|-------|---------|
| Unit Tests | 63 | Function-level correctness |
| Fuzz Tests | 24 | Random input validation |
| Invariant Tests | 15 | Protocol-wide properties |
| **Total** | **102** | |

### Testing Methodology

**Unit Tests** - Verify each function behaves correctly:
- Role restrictions enforced
- State changes as expected
- Events emitted properly
- Edge cases handled (zero amounts, zero addresses)

**Fuzz Tests** - Random inputs to find edge cases:
- `testFuzz_CalculateTax` - Tax calculation with random amounts
- `testFuzz_DistributeReward` - Reward distribution bounds
- `testFuzz_Transfer_TaxDeduction` - Transfer tax accuracy

**Invariant Tests** - Properties that must always hold:
- Total supply never increases (only decreases via burns)
- Sum of balances equals total supply
- Tax rate never exceeds 10%
- Reward pool balance never exceeds treasury balance

### Run Tests

```bash
forge test                           # All tests
forge test --match-test testFuzz     # Fuzz tests only
forge test --match-contract Invariant # Invariant tests
forge test --gas-report              # With gas benchmarks
```

## RPC Node Plan

### Requirements

The RPC node handles high-frequency micro-reward transactions. Requirements:

| Requirement | Target |
|-------------|--------|
| Latency | < 500ms response time |
| Throughput | 100+ tx/second capacity |
| Uptime | 99.9% availability |
| Redundancy | Multiple node failover |

### Infrastructure

**Recommended Setup:**

```
                    ┌─────────────────┐
                    │  Load Balancer  │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
    ┌────▼────┐         ┌────▼────┐         ┌────▼────┐
    │ RPC #1  │         │ RPC #2  │         │ RPC #3  │
    │ Primary │         │ Primary │         │ Backup  │
    └─────────┘         └─────────┘         └─────────┘
```

**Provider Options:**
- Alchemy (recommended) - Enhanced APIs, rate limiting
- QuickNode - Low latency for high-frequency
- Self-hosted Geth/Reth - Maximum control

### Backend Integration

```typescript
import { ethers } from 'ethers';

class RewardService {
    private provider: ethers.JsonRpcProvider;
    private wallet: ethers.Wallet;
    private token: ethers.Contract;

    constructor() {
        this.provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
        this.wallet = new ethers.Wallet(process.env.REWARD_MANAGER_KEY, this.provider);
        this.token = new ethers.Contract(TOKEN_ADDRESS, TOKEN_ABI, this.wallet);
    }

    async distributeReward(recipient: string, amount: bigint): Promise<string> {
        // 1. Verify time-bank requirement met (off-chain)
        // 2. Check reward pool has sufficient balance
        const poolBalance = await this.token.rewardPoolBalance();
        if (poolBalance < amount) throw new Error('Insufficient pool');

        // 3. Execute distribution
        const tx = await this.token.distributeReward(recipient, amount);
        return tx.hash;
    }
}
```

### Event Monitoring

```typescript
// Real-time tracking for leaderboards
token.on('RewardDistributed', (recipient, amount, poolRemaining, timestamp) => {
    updateLeaderboard(recipient, amount);
    logDistribution(recipient, amount, timestamp);
});

// Monitor tax collection for reservoir
token.on('TaxCollected', (from, to, taxAmount, netAmount) => {
    updateReservoirBalance(taxAmount);
});
```

### Gas Optimization

| Operation | Gas Used | Est. Cost (Base L2) |
|-----------|----------|---------------------|
| distributeReward | ~65,000 | ~$0.001 |
| batchDistributeRewards (10) | ~250,000 | ~$0.004 |
| transfer (with tax) | ~85,000 | ~$0.001 |

## Deployment

### Environment Setup

```env
PRIVATE_KEY=your_private_key
TREASURY_ADDRESS=0x...
RESERVOIR_ADDRESS=0x...
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_KEY
```

### Deploy

```bash
forge script script/DeployACTX.s.sol:DeployACTX --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv
```

## Project Structure

```
actx-token/
├── src/
│   ├── ACTXToken.sol      # Main token (UUPS proxy)
│   ├── Airdrop.sol        # Merkle airdrop
│   └── Vesting.sol        # Team vesting
├── test/
│   ├── ACTXToken.t.sol
│   ├── ACTXTokenInvariant.t.sol
│   ├── Airdrop.t.sol
│   └── Vesting.t.sol
├── script/
│   └── DeployACTX.s.sol
└── DEPLOYMENTS.md
```

## License

MIT
