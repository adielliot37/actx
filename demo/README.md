# ACT.X Token Demo Dashboard

A sleek black and white demo interface with **real smart contract integration** for ACT.X Token.

## Features

- **Real Contract Integration**: Connects to deployed ACTXToken on Sepolia testnet
- **Wallet Connection**: MetaMask integration for transaction signing
- **Dashboard**: Live on-chain token statistics
- **Reward Distribution**: Actually distribute rewards (requires REWARD_MANAGER_ROLE)
- **Transaction Tax**: Test real transfers with tax calculation
- **Role Management**: View contract roles and permissions
- **Event Tracking**: Real-time on-chain events and leaderboard

## Setup

```bash
cd demo
npm install
npm run dev
```

Open http://localhost:3000

## Usage

1. **Connect Wallet**: Click "CONNECT WALLET" and approve MetaMask connection
2. **Switch Network**: Ensure you're on Sepolia testnet (Chain ID: 11155111)
3. **Interact**: Use the dashboard to view stats, distribute rewards, test transfers, etc.

## Contract Addresses

- **ACTXToken (Proxy)**: `0x393F332Da314C411cD4B577e3aD433a7DeB54b4b`
- **Network**: Sepolia Testnet

## Requirements

- MetaMask or compatible Web3 wallet
- Sepolia testnet ETH for gas fees
- REWARD_MANAGER_ROLE to distribute rewards (or use test account with role)

## Build

```bash
npm run build
```

## Design

- Black and white color scheme
- Clean, minimalist aesthetic
- Responsive design
- Real-time on-chain data
- No code comments (as requested)

