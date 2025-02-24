# Ikigai Labs V2 Protocol

<div align="center">

![Ikigai Labs Logo](logo.png)

[![Discord](https://img.shields.io/discord/YOUR_DISCORD_ID?color=7289da&label=Discord&logo=discord&logoColor=ffffff)](https://discord.gg/ikigailabs)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

*Empowering AI art collectors through staking, rewards, and governance*

[Documentation](https://docs.ikigailabs.xyz) | [Discord](https://discord.gg/ikigailabs) | [Website](https://ikigailabs.xyz)

</div>

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Features](#-features)
- [Integration](#-integration)
- [Development](#-development)
- [Security](#-security)
- [Tokenomics](#-tokenomics)
- [Support](#-support)

## 🌟 Overview

The Ikigai V2 Protocol revolutionizes AI art collection by seamlessly integrating with [ikigailabs.xyz](https://ikigailabs.xyz). Our protocol enhances the collecting experience through:

- **Automated Rewards** for minting and trading
- **Tiered Benefits** based on staking amounts
- **Governance Features** for community curation
- **Enhanced Trading** via Reservoir integration

## 🎯 Features

### Collector Benefits

| Tier | Requirement | Mint Discount | Staking Bonus | Benefits |
|------|-------------|---------------|---------------|-----------|
| 🥇 Gold | 15,000 IKIGAI | 25% | 50% | Priority Access, Max Rewards |
| 🥈 Silver | 5,000 IKIGAI | 10% | 20% | Enhanced Rewards, Early Access |
| 🥉 Bronze | 1,000 IKIGAI | 5% | 10% | Base Rewards, Community Access |

### Staking Features

- 📈 Dynamic APY based on lock period
- 🎨 Exclusive access to limited editions
- 🗳️ Governance voting power
- ⚡ Priority minting rights

### Trading Integration

- 🌊 Seamless Reservoir protocol integration
- 💹 Real-time market analytics
- 🏷️ Smart pricing suggestions
- 🎁 Trading rewards and referrals

## 🔗 Integration

### Quick Start

```typescript
import { IkigaiV2Protocol } from '@ikigai/v2-sdk'
import { useReservoirClient } from '@reservoir0x/reservoir-kit-ui'

// Initialize protocol
const protocol = new IkigaiV2Protocol({
  network: 'mainnet',
  apiKey: YOUR_API_KEY
})

// Use enhanced market features
const { getEnhancedMarketStats } = useEnhancedReservoir(collectionAddress)
const stats = await getEnhancedMarketStats()
```

### Key Components

1. **Artwork Minting**
```typescript
const { mintWithRewards } = useArtworkMinting(collectionAddress)
const result = await mintWithRewards(artworkId)
```

2. **Staking Management**
```typescript
const { stake, calculateRewards } = useStakingV2()
await stake(amount, lockPeriod)
```

3. **Market Actions**
```typescript
const { executeTrade } = useProtocolMarketActions()
await executeTrade(orderDetails)
```

## 🛠️ Development

### Prerequisites

- Node.js ≥ 16
- Yarn
- Ethereum wallet

### Setup

1. **Clone Repositories**
```bash
git clone https://github.com/IkigaiLabsETH/ikigai-v2-protocol
git clone https://github.com/IkigaiLabsETH/ikigailabs.xyz
```

2. **Install Dependencies**
```bash
cd ikigai-v2-protocol
yarn install

cd ../ikigailabs.xyz
yarn install
```

3. **Configure Environment**
```bash
cp .env.example .env.local
```

Required environment variables:
- \`NEXT_PUBLIC_REWARDS_ADDRESS\`
- \`NEXT_PUBLIC_STAKING_ADDRESS\`
- \`NEXT_PUBLIC_TREASURY_ADDRESS\`

### Development Flow

1. **Start Protocol**
```bash
yarn hardhat node
yarn deploy:local
```

2. **Start Frontend**
```bash
yarn dev
```

3. **Run Tests**
```bash
yarn test                # All tests
yarn test:rewards       # Rewards tests
yarn test:staking      # Staking tests
yarn test:treasury     # Treasury tests
```

## 🔒 Security

### Smart Contract Security

- ✅ Role-based access control
- 🔐 Multi-sig requirements
- ⏰ Time-locked admin actions
- 🛑 Circuit breakers
- 📊 Rate limiting

### Monitoring

- 🔍 Real-time transaction monitoring
- 🐋 Whale watching
- ⚡ Flash loan detection
- 💰 Treasury management

## 💎 Tokenomics

### Token Metrics

- **Supply**: 1,000,000,000 IKIGAI
- **Daily Mint**: 684,931 IKIGAI (~250M annually)
- **Max Transaction**: 1,000,000 IKIGAI

### Fee Structure

Trading Fee: 2.5% distributed as:
- 50% to Staking Rewards
- 30% to Liquidity Pool
- 15% to Treasury Operations
- 5% to Token Burns

## 💬 Support

- **Discord**: [Join our community](https://discord.gg/ikigailabs)
- **Documentation**: [docs.ikigailabs.xyz](https://docs.ikigailabs.xyz)
- **Email**: support@ikigailabs.xyz

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

<div align="center">
Made with 💜 by Ikigai Labs
</div>
