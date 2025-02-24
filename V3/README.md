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

# Ikigai V3 Protocol

## Buyback Mechanics

### Overview
The Ikigai V3 Protocol features a sophisticated buyback system that automatically collects fees from multiple revenue streams and executes strategic token buybacks based on market conditions.

### Revenue Sources
| Source | Allocation | Description |
|--------|------------|-------------|
| Trading Fees | 25% | From all trading activity |
| NFT Sales | 30% | Primary and secondary sales |
| Treasury Yield | 20% | From treasury investments |
| Transfer Tax | 1% | On token transfers |
| Staking Fees | 20% | From staking operations |

### Buyback Engine

#### Pressure System
- Base Pressure: 50% of accumulated funds
- Maximum Pressure: 80% of accumulated funds
- Dynamic adjustment based on price levels:

| Price Level | Pressure Increase | Total Pressure |
|-------------|------------------|----------------|
| $0.50 | +5% | 55% |
| $0.40 | +10% | 60% |
| $0.30 | +15% | 65% |
| $0.20 | +20% | 70% |
| $0.10 | +25% | 75% |

#### Safety Parameters
```solidity
struct SafetyLimits {
    uint256 minBuyback: 100 tokens,    // Minimum execution size
    uint256 cooldown: 24 hours,        // Between buybacks
    uint256 slippage: 0.5%,           // Maximum allowed
    uint256 minLiquidity: $1M,        // Required depth
    uint256 maxImpact: 2%,            // Per depth level
    uint256 depthRatio: 50%           // Minimum required
}
```

#### Execution Flow
1. Revenue Collection
   - Multiple sources feed buyback pool
   - Automatic allocation tracking
   - Accumulation until threshold met

2. Buyback Trigger
   ```typescript
   conditions = {
     timePassed: > 24 hours,
     minFunds: >= 100 tokens,
     liquidityOK: true
   }
   ```

3. Smart Execution
   - Dynamic pressure calculation
   - Liquidity depth analysis
   - Size optimization
   - Market buy execution
   - Token distribution

### Distribution
- 80% of bought tokens are burned
- 20% to staking rewards pool

### Integration Points

#### Core Contracts
```solidity
interface IBuybackEngine {
    function executeBuyback() external;
    function collectRevenue(bytes32 source, uint256 amount) external;
    function calculatePressure(uint256 currentPrice) external view returns (uint256);
}
```

#### Revenue Collection
```solidity
// In V2.sol
function transfer(address to, uint256 amount) public override returns (bool) {
    uint256 buybackAmount = amount * BUYBACK_TAX / 10000; // 1%
    buybackEngine.collectRevenue("TRANSFER_FEES", buybackAmount);
    // ... transfer logic
}
```

### Monitoring & Analytics

#### Key Metrics
- Accumulated funds
- Last buyback time
- Revenue stream stats
- Liquidity depth analysis
- Price impact measurements

#### Events
```solidity
event BuybackExecuted(
    uint256 amount,
    uint256 tokensBought,
    uint256 tokensBurned,
    uint256 tokensToRewards
);

event RevenueCollected(
    bytes32 indexed source,
    uint256 amount,
    uint256 buybackAllocation
);
```

### Safety Features

#### Circuit Breakers
- Price-based triggers
- Volume anomaly detection
- Liquidity protection
- Manual override capability

#### Recovery Procedures
- System pause functionality
- Fund recovery mechanisms
- State reset capabilities
- Emergency fund protection

### Performance Optimization

#### Gas Efficiency
- Batched operations
- Optimized state updates
- Minimal external calls
- Strategic execution timing

#### Market Impact
- Smart order sizing
- Liquidity analysis
- Impact minimization
- Execution splitting

## Contract Integration

### V2 Token
```solidity
// Buyback parameters
uint256 public constant BUYBACK_TAX = 100; // 1% tax
uint256 public constant MIN_BUYBACK_AMOUNT = 1000e18;
bool public buybackEnabled = true;

// Integration
IBuybackEngine public buybackEngine;
```

### StakingV2
```solidity
// Buyback allocation
uint256 public constant STAKING_BUYBACK_SHARE = 2000; // 20%
IBuybackEngine public buybackEngine;
```

### RewardsV2
```solidity
// Trading fee buyback
uint256 public constant TRADING_BUYBACK_SHARE = 2500; // 25%
IBuybackEngine public buybackEngine;
```

### TreasuryV2
```solidity
// Treasury yield buyback
uint256 public constant BUYBACK_SHARE = 2000; // 20%
IBuybackEngine public buybackEngine;
```

## Testing & Deployment

### Test Coverage
- Revenue collection
- Buyback execution
- Pressure calculation
- Safety parameters
- Emergency procedures

### Deployment Steps
1. Deploy BuybackEngine
2. Deploy V2 token with buyback
3. Configure revenue sources
4. Set up monitoring
5. Enable buyback system

### Security Considerations
- Rate limiting on buybacks
- Slippage protection
- Liquidity validation
- Access control
- Emergency stops

[Additional protocol documentation...]
