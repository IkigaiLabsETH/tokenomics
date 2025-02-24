# Ikigai Protocol

A comprehensive NFT marketplace and reward system on BeraChain, featuring dynamic rewards, trading incentives, and automated liquidity management.

## Core Features

### NFT Marketplace (via Reservoir)
- Seamless trading experience
- Priority minting for BeraChain NFT holders
- Automated reward distribution
- Transparent fee structure

### Dynamic Reward System
1. **Trading Rewards**
   - Base reward: 3% in IKIGAI tokens
   - Combo multipliers (up to 5x)
   - 24-hour combo window
   - Volume-based milestones

2. **Minting Rewards**
   - 5% reward for minting NFTs
   - Priority minting discounts
   - BeraChain NFT holder benefits
   - Minting rewards vesting:
     - 3 month linear vesting
     - 1 week cliff period
     - Claimable in portions
     - Transparent tracking

3. **Staking Rewards**
   - 2% base staking reward
   - Tiered multipliers
   - Lock period bonuses
   - Compound rewards

4. **Referral Program**
   - 1% referral rewards
   - Unlimited referrals
   - Instant distribution
   - Transparent tracking

### Reward Mechanics

#### Trading Combos
- Each trade within 24h increases combo
- 0.1% bonus per combo level
- Maximum 5x multiplier
- Auto-reset after 24h inactivity

#### Volume Milestones
- Level 1: 10 BERA = 5 IKIGAI
- Level 2: 100 BERA = 50 IKIGAI
- Level 3: 500 BERA = 400 IKIGAI
- Level 4: 1000 BERA = 1000 IKIGAI

#### Staking Tiers
- Base: 1x rewards
- Silver: 1.25x rewards
- Gold: 1.5x rewards
- Diamond: 2x rewards

## Technical Integration

### Smart Contracts
- `IkigaiToken.sol`: ERC20 token with marketplace and deflationary features
- `IkigaiNFT.sol`: NFT contract with staking and reward distribution

### Reservoir Integration
```typescript
// Example usage
const reservoir = new ReservoirSDK({
    apiKey: RESERVOIR_API_KEY,
    chainId: 1 // BeraChain
});

// Listen for sales
reservoir.sales.subscribe((sale) => {
    // Reward distribution
});
```

### Fee Structure
Total: 4.3% of transactions
- 2% Protocol Owned Liquidity
- 1.3% Staking Rewards
- 1% Treasury Operations

## Development

### Prerequisites
- Node.js v23
- Hardhat
- Foundry (optional)

### Setup
```bash
# Install dependencies
yarn install

# Compile contracts
yarn contracts:compile

# Run tests
yarn contracts:test
```

### Deployment
```bash
# Deploy to BeraChain
yarn contracts:deploy:berachain
```

## Security Features & Architecture

### Core Security Mechanisms

1. Access Control Layers
```solidity
// Example implementation
modifier onlyWhitelisted() {
    require(whitelisted[msg.sender], "Not whitelisted");
    _;
}
```
- Role-based permissions (Owner, Strategist, Rebalancer)
- Whitelist system for critical operations
- Granular function access control
- Multi-signature support for critical functions

2. Rate Limiting
```solidity
struct RateLimit {
    uint256 lastActionTime;
    uint256 actionCount;
    uint256 windowStart;
}
```
- Per-action cooldowns
- Maximum actions per time window
- Graduated limits based on user tier
- Anti-spam protection

3. Circuit Breakers
```solidity
bool public emergencyMode;
uint256 public lastEmergencyAction;
uint256 public constant EMERGENCY_TIMEOUT = 24 hours;
```
- Emergency pause functionality
- Tiered shutdown mechanisms
- Automatic suspension triggers
- Recovery timeouts

4. Transaction Guards
```solidity
modifier validAmount(uint256 amount) {
    require(amount > 0 && amount <= MAX_SINGLE_TRANSFER, "Invalid amount");
    _;
}
```
- Maximum transaction limits
- Slippage protection
- Price impact checks
- Balance/allowance validation

### Security Features by Contract

#### IkigaiToken
- Adaptive burn rate based on market cap
- Transfer limits and cooldowns
- Contract interaction restrictions
- Liquidity protection mechanisms

#### IkigaiNFT
- Stake amount validation
- Rate-limited minting
- Tiered access control
- Emergency withdrawal system

#### IkigaiMarketplace
- Price validation
- Royalty limits
- Auction safety checks
- Batch operation limits

#### IkigaiRewards
- Reward calculation safety
- Distribution rate limits
- Combo system protection
- Vesting schedule security

#### IkigaiTreasury
- Rebalancing thresholds
- Liquidity ratio protection
- Fee distribution safety
- Emergency recovery system

### Protection Mechanisms

1. Value Protection
```solidity
uint256 private constant MAX_PRICE = 1_000_000 * 1e18; // 1M BERA max
uint256 private constant MIN_LIQUIDITY = 1000 * 1e18;  // 1000 BERA min
```
- Maximum value caps
- Minimum threshold requirements
- Value relationship checks
- Overflow protection

2. Time Protection
```solidity
uint256 public constant ACTION_COOLDOWN = 1 hours;
uint256 public constant MIN_REBALANCE_INTERVAL = 1 days;
```
- Action cooldowns
- Minimum intervals
- Maximum durations
- Timestamp validation

3. State Protection
```solidity
mapping(address => bool) public blacklisted;
mapping(address => uint256) public lastActionTime;
```
- State machine validation
- Reentrancy guards
- Operation ordering
- State transition checks

4. Asset Protection
```solidity
function emergencyWithdraw() external nonReentrant notBlacklisted(msg.sender) {
    require(emergencyMode, "Not in emergency mode");
    // ... safe withdrawal logic
}
```
- Safe transfer patterns
- Return value checking
- Balance validation
- Emergency recovery

### Security Events & Monitoring

1. Security Events
```solidity
event SecurityIncident(
    address indexed account,
    string incidentType,
    uint256 timestamp
);
```
- Security incident logging
- Rate limit violations
- Emergency mode changes
- Critical state updates

2. Monitoring Hooks
```solidity
event SecurityLimitExceeded(
    address indexed account,
    string limitType,
    uint256 amount,
    uint256 limit
);
```
- Transaction monitoring
- Rate limit tracking
- Value threshold alerts
- State change notifications

### Emergency Procedures

1. Emergency Mode
```solidity
function enableEmergencyMode() external onlyOwner {
    emergencyMode = true;
    lastEmergencyAction = block.timestamp;
    emit EmergencyModeEnabled(block.timestamp);
}
```
- Activation conditions
- Cooldown periods
- Recovery procedures
- Asset protection

2. Recovery Functions
```solidity
function emergencyWithdraw(
    address token,
    address recipient,
    uint256 amount
) external onlyOwner {
    require(emergencyMode, "Not in emergency");
    // ... safe withdrawal logic
}
```
- Asset recovery
- State reset
- Access restoration
- System restoration

### Security Best Practices

1. Code Patterns
- Check-Effects-Interaction pattern
- Pull over push payments
- Secure function ordering
- Safe math operations

2. Testing Requirements
- Comprehensive unit tests
- Integration testing
- Fuzzing/property testing
- Security scenario testing

3. Deployment Process
- Multi-signature deployment
- Gradual rollout
- Emergency contacts
- Incident response plan

4. Maintenance
- Regular audits
- Upgrade procedures
- Bug bounty program
- Security monitoring

## Support & Documentation

- [Reservoir Docs](https://docs.reservoir.tools/)
- [BeraChain Docs](https://docs.berachain.com/)
- [Technical Docs](./docs/TECHNICAL.md)
- [API Reference](./docs/API.md)

## License

MIT License

## Tokenomics

### IKIGAI Token Overview
- **Token Standard**: ERC20
- **Symbol**: IKIGAI
- **Maximum Supply**: 1,000,000,000 (1 billion)
- **Initial Supply**: 0 (fair launch)
- **Decimals**: 18

### NFT Collections
- **Genesis Series**
  - Mint with BERA
  - Get IKIGAI rewards (vested)
  - Priority access for BeraChain NFT holders
  - Whitelist support with discounts

- **Post-Genesis Series**
  - Mint with IKIGAI tokens
  - 20% of mint price burned
  - 60% to treasury
  - 20% to staking rewards
  - Staking Requirements:
    - Minimum stake amount required
    - Lock duration requirements
    - Tier-based discounts
    - Whitelist benefits

### Minting Mechanics
**Staking Discounts**:
- 5,000 IKIGAI staked = 10% off mint price
- 10,000 IKIGAI staked = 20% off mint price
- 25,000 IKIGAI staked = 30% off mint price

**Whitelist Benefits**:
- Early access to new series
- Additional price discounts
- Guaranteed mint slots
- Combinable with staking discounts

**Series Requirements**:
- Genesis: Pay in BERA, get vested IKIGAI
- Series 1+: Requires IKIGAI stake
- Higher series = higher stake requirements
- Longer stake duration = better benefits

### Token Distribution & Emissions
**Initial Distribution**:
- 0% Team/Advisors (no pre-mine)
- 0% Private Sale
- 100% through protocol activities

**Emission Schedule**:
- Year 1: Maximum 250M tokens (25%)
- Year 2: Maximum 200M tokens (20%)
- Year 3: Maximum 150M tokens (15%)
- Year 4+: Determined by protocol activity

**Emission Sources**:
- Trading Volume (40% of emissions)
- NFT Minting (30% of emissions)
- Staking Rewards (20% of emissions)
- Referrals & Combos (10% of emissions)

### Advanced Reward Mechanisms
**Dynamic Reward Calculation**:
- Market Activity Multiplier:
  - 1.5x when daily volume > 1000 BERA
  - Automatically adjusts based on activity
  - Encourages active trading periods

- User Performance Multipliers:
  - Trade Streak: +15% per day (max 100%)
  - Staking Duration: Up to 50% bonus
  - Monthly Volume: Up to 100% bonus
  - Compounds with other bonuses

- Combined Multipliers:
  - Base Reward × Market Multiplier
  - + Streak Bonus
  - + Staking Duration Bonus
  - + Volume Tier Bonus
  - Final reward can be up to 4x base

### Dynamic Fee Structure
**Base Fees**: 4.3% total
**Reductions Based On**:
- Staking tier (up to -30%)
- Trading volume (up to -20%)
- Loyalty streak (up to -15%)
- Combined max reduction: 50%

### Protocol Revenue
**Fee Distribution**:
- 40% Buy & Burn
- 30% Staking Rewards
- 20% Treasury
- 10% Development

**Seasonal Allocations**:
- 5% to seasonal rewards
- 3% to NFT rewards
- 2% to boost pool
- Remainder to standard distribution

### Supply Control Mechanisms
**Adaptive Burn Rate**:
- Base: 1% of transactions
- Scales with market cap
- Dynamic adjustment
- Maximum 4% at peak

**Supply Caps**:
- Daily mint limit: 0.1% of supply
- Weekly emission cap: 0.5% of supply
- Monthly maximum: 2% of supply

**Emission Safeguards**:
- Rolling caps
- Market-based adjustments
- Volume-based scaling
- Emergency limits

### Token Utility
**Minting Access**:
- Required for post-genesis series
- Higher stakes = better discounts
- Longer stakes = more benefits

**Governance**:
- Series parameters
- Reward rates
- Protocol fees
- Treasury management

**Staking Benefits**:
- Mint discounts
- Trading fee reductions
- Priority access
- Enhanced rewards

### Trading Controls
- **Transfer Limits**:
  - Maximum transfer: 1M IKIGAI per transaction
  - Cooldown period: 1 minute between transfers
  - Batch limit: 20 operations

- **Anti-Bot Protection**:
  - Trading enabled gradually
  - Transfer cooldowns
  - Blacklist system
  - Rate limiting

### Staking Mechanism
- **Lock Periods**:
  - Base Tier: 1 week
  - Silver: 2 weeks
  - Gold: 3 weeks
  - Diamond: 4 weeks

- **Minimum Stakes**:
  - Base: 1,000 IKIGAI
  - Silver: 5,000 IKIGAI
  - Gold: 10,000 IKIGAI
  - Diamond: 25,000 IKIGAI

### Treasury Operations
- **Protocol Owned Liquidity**:
  - 2% of all fees to POL
  - Dynamic rebalancing
  - Minimum liquidity thresholds
  - Automated LP management

- **Revenue Distribution**:
  - 50% to staking rewards
  - 30% to liquidity
  - 20% to treasury operations

### Security Features
- **Trading Controls**:
  - Configurable limits
  - Emergency pause
  - Blacklist system
  - Rate limiting

- **Access Control**:
  - Role-based permissions
  - Multi-sig treasury
  - Time-locked upgrades
  - Emergency controls

### Reward Distribution
**Seasonal Structure**:
- Regular seasons (30-120 days)
- Special events/holidays
- Competitive leaderboards
- Exclusive NFT rewards

**Point System**:
- Trading volume (base points)
- Loyalty multipliers
- Staking bonuses
- Seasonal boosts

**Special Events**:
- Holiday themes
- Flash events
- Community challenges
- Bonus periods

### Emission Controls
**Dynamic Limits**:
- Daily: 0.1% of supply
- Weekly: 0.5% of supply
- Monthly: 2% of supply

**Event Adjustments**:
- Event boost periods
- Holiday multipliers
- Special mint windows
- Dynamic caps

### Supply Control
**Adaptive Mechanics**:
- Market cap scaling
- Volume-based limits
- Emergency controls

**Event Controls**:
- Event-specific caps
- Boosted period limits
- Special event reserves
- Holiday allocations

## Contract Structure

### Core Contracts
- `IkigaiToken.sol`: ERC20 token with marketplace and deflationary features
- `IkigaiNFT.sol`: NFT contract with staking and reward distribution

### Marketplace Contracts
- `IkigaiMarketplace.sol`: NFT marketplace operations
- `IkigaiController.sol`: Marketplace control and configuration

### Reward System
- `IkigaiRewards.sol`: Handles reward distribution from marketplace sales

### Treasury Management
- `IkigaiTreasury.sol`: Protocol treasury and liquidity management

### Libraries
- `Constants.sol`: Shared constants
- `Types.sol`: Common types and structures

# Buyback System

## Overview
The Ikigai Protocol implements an advanced automated buyback system with dynamic pressure mechanics and strategic token burns, enhancing token value and market stability.

## Core Mechanics

### Revenue Collection
| Source | Allocation | Description |
|--------|------------|-------------|
| Trading Fees | 30% | From all trading activity |
| NFT Sales | 35% | Primary and secondary sales |
| Treasury Yield | 25% | From treasury investments |
| Transfer Tax | 2-5% | Tiered based on amount |
| Staking Fees | 25% | From staking operations |

### Distribution
- **90% Burn Rate**: Increased burn ratio for stronger deflation
- **10% Rewards**: Reduced rewards allocation
- **30% Reserve**: Long-term stability buffer
- **10% Bull Market**: Reserved for above $1.00 buybacks

### Safety Parameters
```solidity
struct SafetyLimits {
    uint256 cooldown: 12 hours,        // Reduced cooldown
    uint256 emergencyThreshold: 20%,   // Price drop trigger
    uint256 minLiquidity: 1%,          // Of market cap
    uint256 maxImpact: 2%,            // Per depth level
    uint256 depthRatio: 50%           // Minimum required
}
```

### Transfer Tax Tiers
| Amount | Tax Rate |
|--------|----------|
| <100K  | 2% |
| 100K-500K | 3% |
| >500K | 5% |

## Smart Execution

### Liquidity Analysis
```typescript
const DEPTH_ANALYSIS = {
  steps: 5,
  minDepth: 1000e18,  // $1M
  maxImpact: 200,     // 2%
  depthRatio: 5000    // 50%
}
```

### Execution Flow
1. **Revenue Collection**
   - Multiple sources feed buyback pool
   - Automatic allocation tracking
   - Accumulation until threshold met

2. **Buyback Trigger**
   ```typescript
   conditions = {
     timePassed: > 24 hours,
     minFunds: >= 100 tokens,
     liquidityOK: true
   }
   ```

3. **Smart Execution**
   - Dynamic pressure calculation
   - Liquidity depth analysis
   - Size optimization
   - Market buy execution
   - Token distribution

## Contract Integration

### Core Interfaces
```solidity
interface IBuybackEngine {
    function executeBuyback() external;
    function collectRevenue(bytes32 source, uint256 amount) external;
    function calculatePressure(uint256 currentPrice) external view returns (uint256);
}
```

### Contract Parameters
```solidity
// V2 Token
uint256 public constant BUYBACK_TAX = 100; // 1% tax
uint256 public constant MIN_BUYBACK_AMOUNT = 1000e18;

// StakingV2
uint256 public constant STAKING_BUYBACK_SHARE = 2000; // 20%

// RewardsV2
uint256 public constant TRADING_BUYBACK_SHARE = 2500; // 25%

// TreasuryV2
uint256 public constant BUYBACK_SHARE = 2000; // 20%
```

## Safety Features

### Circuit Breakers
- Price-based triggers
- Volume anomaly detection
- Liquidity protection
- Manual override capability

### Recovery Procedures
- System pause functionality
- Fund recovery mechanisms
- State reset capabilities
- Emergency fund protection

## Monitoring

### Key Metrics
- Accumulated funds
- Last buyback time
- Revenue stream stats
- Liquidity depth analysis
- Price impact measurements

### Events
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

## Performance Optimization

### Gas Efficiency
- Batched operations
- Optimized state updates
- Minimal external calls
- Strategic execution timing

### Market Impact
- Smart order sizing
- Liquidity analysis
- Impact minimization
- Execution splitting
