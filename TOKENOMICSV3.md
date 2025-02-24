# IKIGAI V3 Tokenomics

## Advanced Tokenomics Architecture

The IKIGAI protocol implements a sophisticated tokenomics system designed for long-term sustainability, user engagement, and value accrual. This document outlines the key components and mechanisms that drive the IKIGAI ecosystem.

```
┌─────────────────────────────────────────────────────────────────┐
│                      IKIGAI TOKENOMICS V3                       │
└───────────────────────────────┬─────────────────────────────────┘
                                │
           ┌───────────────────┴────────────────────┐
           ▼                    ▼                    ▼
┌─────────────────────┐ ┌─────────────────┐ ┌─────────────────────┐
│  VALUE GENERATION   │ │ VALUE CAPTURE   │ │   VALUE ACCRUAL     │
└─────────┬───────────┘ └────────┬────────┘ └──────────┬──────────┘
          │                      │                     │
    ┌─────┴─────┐          ┌─────┴─────┐         ┌─────┴─────┐
    ▼           ▼          ▼           ▼         ▼           ▼
┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐
│  NFT    │ │ Staking │ │ Buyback │ │ Fee     │ │ Burn    │ │ Voting  │
│ Sales   │ │ Rewards │ │ Engine  │ │ Capture │ │ Mech.   │ │ Power   │
└─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘
```

## 1. Core Tokenomics Components

### 1.1 Referral System with Token Incentives

The referral system creates viral growth incentives by rewarding community advocates who bring new users to the platform.

```solidity
mapping(address => address) public referrers;
mapping(address => uint256) public referralRewards;
uint256 public referralRewardBps = 500; // 5% of mint price
```

**Key Features:**
- 5% of mint price rewarded to referrers
- Automatic tracking of referral relationships
- Claimable rewards for community advocates
- Creates viral growth incentives

```
┌──────────────────┐         refers         ┌──────────────────┐
│                  │ ──────────────────────>│                  │
│    User A        │                        │     User B       │
│                  │                        │                  │
└──────────────────┘                        └──────────────────┘
         │                                           │
         │ claims                                    │ mints
         │ rewards                                   │ NFT
         ▼                                           ▼
┌──────────────────┐                        ┌──────────────────┐
│    5% Reward     │<───────────────────────│   95% Protocol   │
└──────────────────┘                        └──────────────────┘
```

### 1.2 Cross-Collection NFT Synergies

The cross-collection synergy system encourages users to collect across multiple NFT collections in the ecosystem, creating stronger network effects.

```solidity
address[] public registeredCollections;
mapping(address => bool) public isRegisteredCollection;
uint256 public collectionBonusBps = 250; // 2.5% per collection
uint256 public maxCollectionBonus = 1000; // 10% max
```

**Key Features:**
- 2.5% discount per additional collection owned
- Up to 10% maximum collection bonus
- Encourages ecosystem-wide collecting
- Rewards dedicated community members

```
┌─────────────────────────────────────────────────────────────────┐
│                     COLLECTION BONUS SYSTEM                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                ┌─────────────┼─────────────┐
                ▼             ▼             ▼
        ┌───────────┐  ┌───────────┐  ┌───────────┐
        │Collection1│  │Collection2│  │Collection3│  ...
        └───────────┘  └───────────┘  └───────────┘
                │             │             │
                └─────────────┼─────────────┘
                              ▼
                     ┌─────────────────┐
                     │  Bonus Formula  │
                     │ min(n*2.5%, 10%)│
                     └─────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │  Mint Discount  │
                     └─────────────────┘
```

### 1.3 Composable Staking Positions

The composable staking system allows users to optimize their staking positions by combining multiple stakes into a single position.

```solidity
function combineStakes(uint256[] calldata _stakeIds) external nonReentrant returns (uint256) {
    // Implementation details...
    // Calculate weighted lock period
    weightedLockPeriod = weightedLockPeriod / totalAmount;
    // Create new combined stake
    uint256 newStakeId = _createStake(totalAmount, weightedLockPeriod);
}
```

**Key Features:**
- Allows users to optimize their staking positions
- Reduces contract storage overhead
- Creates more flexible staking strategies
- Improves capital efficiency

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Stake #1   │    │  Stake #2   │    │  Stake #3   │
│ 1000 IKIGAI │    │ 2000 IKIGAI │    │ 3000 IKIGAI │
│  30 days    │    │  60 days    │    │  90 days    │
└──────┬──────┘    └──────┬──────┘    └──────┬──────┘
       │                  │                  │
       └──────────┬───────┴──────────┬───────┘
                  │                  │
                  ▼                  ▼
         ┌────────────────────────────────┐
         │        Combined Stake          │
         │         6000 IKIGAI            │
         │ (1000*30 + 2000*60 + 3000*90)  │
         │   ÷ 6000 = ~70 days lock       │
         └────────────────────────────────┘
```

### 1.4 Protocol-Owned NFT Vault

The protocol-owned NFT vault allows the protocol to acquire and hold strategic NFTs, creating sustainable revenue streams.

```solidity
// Revenue sharing
uint256 public constant BUYBACK_SHARE_BPS = 2000; // 20% to buyback
uint256 public constant TREASURY_SHARE_BPS = 8000; // 80% to treasury
```

**Key Features:**
- Protocol acquires and holds strategic NFTs
- 20% of NFT sale revenue to buyback and burn
- 80% to treasury for protocol development
- Creates sustainable protocol-owned assets

```
┌─────────────────────────────────────────────────────────────────┐
│                     PROTOCOL NFT VAULT                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
                      ┌───────────────────┐
                      │   NFT Portfolio   │
                      └─────────┬─────────┘
                                │
                                ▼
                      ┌───────────────────┐
                      │   Sale Revenue    │
                      └─────────┬─────────┘
                                │
              ┌─────────────────┴─────────────────┐
              ▼                                   ▼
    ┌───────────────────┐               ┌───────────────────┐
    │      20% to       │               │      80% to       │
    │     Buyback       │               │     Treasury      │
    └─────────┬─────────┘               └─────────┬─────────┘
              │                                   │
              ▼                                   ▼
    ┌───────────────────┐               ┌───────────────────┐
    │    Token Burn     │               │  Protocol Growth  │
    └───────────────────┘               └───────────────────┘
```

### 1.5 Algorithmic Buyback Pressure

The algorithmic buyback system creates counter-cyclical market support by adjusting buyback amounts based on market conditions.

```solidity
function calculateOptimalBuybackAmount() public view returns (uint256) {
    // Get current price and 30-day average
    uint256 currentPrice = getCurrentPrice();
    uint256 thirtyDayAvg = getThirtyDayAveragePrice();
    
    // Calculate price deviation
    uint256 deviation = 0;
    if (currentPrice < thirtyDayAvg) {
        deviation = ((thirtyDayAvg - currentPrice) * 10000) / thirtyDayAvg;
    }
    
    // Calculate buyback multiplier based on deviation
    uint256 multiplier = 10000 + (deviation * 3); // +0-30% based on deviation
    
    return (MIN_BUYBACK_AMOUNT * multiplier) / 10000;
}
```

**Key Features:**
- Creates counter-cyclical market support
- Optimizes treasury usage during downtrends
- Reduces buyback waste during uptrends
- Provides algorithmic price stability

```
┌─────────────────────────────────────────────────────────────────┐
│                  ALGORITHMIC BUYBACK SYSTEM                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │  Market Analysis   │
                    └──────────┬─────────┘
                               │
         ┌────────────────────┴────────────────────┐
         ▼                                         ▼
┌──────────────────┐                      ┌──────────────────┐
│  Price Below     │                      │  Price Above     │
│  30-day Average  │                      │  30-day Average  │
└────────┬─────────┘                      └────────┬─────────┘
         │                                         │
         ▼                                         ▼
┌──────────────────┐                      ┌──────────────────┐
│Increase Buyback  │                      │Maintain Baseline │
│Up to +30%        │                      │    Buyback       │
└────────┬─────────┘                      └────────┬─────────┘
         │                                         │
         └─────────────────┬───────────────────────┘
                           │
                           ▼
                 ┌────────────────────┐
                 │  Execute Buyback   │
                 └────────┬───────────┘
                          │
                          ▼
                 ┌────────────────────┐
                 │    Token Burn      │
                 └────────────────────┘
```

### 1.6 Liquidity Position NFTs

The liquidity position NFT system tokenizes LP positions, making them tradable and composable.

```solidity
function mintPositionNFT(
    address _pair,
    uint256 _liquidity,
    uint256 _lockDuration
) external nonReentrant returns (uint256) {
    // Implementation details...
}
```

**Key Features:**
- Makes liquidity positions tradable
- Creates secondary market for LP positions
- Enables LP position composability
- Improves liquidity provider experience

```
┌─────────────────────────────────────────────────────────────────┐
│                   LIQUIDITY POSITION NFTs                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │   LP Token Deposit │
                    └──────────┬─────────┘
                               │
                               ▼
                    ┌────────────────────┐
                    │   Position NFT     │
                    │      Minted        │
                    └──────────┬─────────┘
                               │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│     Trade on     │  │    Stake for     │  │   Use as         │
│  NFT Marketplace │  │ Additional Yield │  │  Collateral      │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

### 1.7 Adaptive Emission Control

The adaptive emission control system adjusts token emission rates based on market conditions to maintain price stability.

```solidity
function adjustEmissionRate() external nonReentrant {
    // Calculate 7-day price volatility
    uint256 volatility = calculate7DayVolatility();
    
    // If volatility is too high, reduce emissions
    if (volatility > TARGET_PRICE_STABILITY) {
        uint256 reduction = (volatility - TARGET_PRICE_STABILITY) / 100;
        reduction = reduction > 20 ? 20 : reduction; // Cap at 20%
        
        baseEmissionRate = baseEmissionRate * (100 - reduction) / 100;
    } 
    // If volatility is low, can slightly increase emissions
    else if (volatility < TARGET_PRICE_STABILITY / 2) {
        baseEmissionRate = baseEmissionRate * 102 / 100; // +2%
    }
}
```

**Key Features:**
- Creates self-regulating token supply
- Reduces price volatility
- Optimizes emission schedule based on market conditions
- Provides algorithmic monetary policy

```
┌─────────────────────────────────────────────────────────────────┐
│                  ADAPTIVE EMISSION CONTROL                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Volatility Analysis│
                    └──────────┬─────────┘
                               │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│  High Volatility │  │ Normal Volatility│  │  Low Volatility  │
│     (>5%)        │  │    (2.5-5%)      │  │     (<2.5%)      │
└────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘
         │                     │                     │
         ▼                     ▼                     ▼
┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
│ Reduce Emissions │  │ Maintain Current │  │Increase Emissions│
│  (up to -20%)    │  │  Emission Rate   │  │      (+2%)       │
└──────────────────┘  └──────────────────┘  └──────────────────┘
```

### 1.8 Milestone-Based Token Unlocks

The milestone-based token unlock system aligns token release with development progress, creating transparent roadmap incentives.

```solidity
struct Milestone {
    string description;
    uint256 tokenAmount;
    bool achieved;
    uint256 unlockTime;
}
```

**Key Features:**
- Transparent roadmap-based token releases
- 30-day delay between achievement and unlocking
- Governance-controlled milestone verification
- Aligns token release with development progress

```
┌─────────────────────────────────────────────────────────────────┐
│                MILESTONE-BASED TOKEN UNLOCKS                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Milestone Achieved │
                    └──────────┬─────────┘
                               │
                               ▼
                    ┌────────────────────┐
                    │   30-Day Delay     │
                    └──────────┬─────────┘
                               │
                               ▼
                    ┌────────────────────┐
                    │   Tokens Unlocked  │
                    └──────────┬─────────┘
                               │
                               ▼
                    ┌────────────────────┐
                    │ Distribution to    │
                    │ Designated Address │
                    └────────────────────┘
```

## 2. Tokenomics Integration Flow

The advanced tokenomics features create a virtuous cycle that drives token value, user engagement, and protocol sustainability:

```
┌─────────────────────────────────────────────────────────────────┐
│                     TOKENOMICS LIFECYCLE                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                        GENESIS PHASE                            │
│                                                                 │
│ • Users mint with BERA tokens                                   │
│ • Receive vested IKIGAI rewards                                 │
│ • Refer friends for additional rewards                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                       ENGAGEMENT PHASE                          │
│                                                                 │
│ • Stake IKIGAI for governance rights and discounts              │
│ • Collect across multiple NFT collections for bonuses           │
│ • Participate in milestone achievements                         │
│ • Provide liquidity and receive LP NFTs                         │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     VALUE ACCRUAL PHASE                         │
│                                                                 │
│ • NFT sales drive buyback and burn                              │
│ • Protocol acquires strategic NFTs                              │
│ • Treasury grows through adaptive fees                          │
│ • Token supply decreases through burns                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
                         ┌─────────────┐
                         │  FEEDBACK   │
                         │    LOOP     │──────┐
                         └─────────────┘      │
                                             ┌┘
                                             │
                                             └─▶ (Back to Genesis Phase)
```

## 3. Economic Parameters

### 3.1 Fee Structure

The adaptive fee structure optimizes fee revenue while encouraging larger transactions:

```solidity
function calculateDynamicFee(uint256 _transactionValue) public view returns (uint256) {
    // Base fee for standard transactions
    uint256 fee = baseFee;
    
    // Reduce fee for large transactions
    if (_transactionValue > 10000e18) { // > 10,000 tokens
        fee = fee * 90 / 100; // 10% discount
    }
    
    // Further reduce for very large transactions
    if (_transactionValue > 100000e18) { // > 100,000 tokens
        fee = fee * 80 / 100; // Additional 20% discount
    }
    
    return fee;
}
```

**Fee Parameters:**
- Base fee: 3% for standard transactions
- Volume discounts for larger transactions:
  - 10% discount for transactions > 10,000 IKIGAI
  - Additional 20% discount for transactions > 100,000 IKIGAI
- Minimum fee: 1%
- Maximum fee: 5%

### 3.2 Staking Rewards

The tiered staking system rewards long-term holders and larger stake amounts:

**Staking Parameters:**
- Base APY: 15%
- Tier 1 (5,000 IKIGAI): +5% APY
- Tier 2 (10,000 IKIGAI): +10% APY
- Tier 3 (25,000 IKIGAI): +15% APY
- Weekly bonus: +0.5% per week of lock duration
- Maximum lock period: 365 days

### 3.3 Emission Schedule

The adaptive emission control system ensures sustainable token distribution:

**Emission Parameters:**
- Initial daily emission: 685,000 IKIGAI
- Weekly reduction: 0.5%
- Target price stability: 5% max volatility
- Maximum emission adjustment: 20% reduction
- Minimum emission after 2 years: 50% of initial rate

## 4. Governance and Voting Power

The governance-weighted staking system aligns voting power with economic commitment:

```solidity
function getVotingPower(address _user) external view returns (uint256) {
    // Voting power increases with stake amount and duration
    return amount * (lockDuration / 30 days) / 4; // Max 4x multiplier
}
```

**Governance Parameters:**
- Base voting power: 1x stake amount
- Duration multiplier: +1x per 30 days of lock
- Maximum multiplier: 4x for 120+ day locks
- Proposal threshold: 1% of total supply
- Quorum requirement: 4% of total supply

## 5. Conclusion

The IKIGAI V3 tokenomics system creates a sophisticated economic framework that aligns incentives across all stakeholders. By implementing advanced mechanisms like algorithmic buybacks, composable staking, and adaptive emissions, the protocol creates sustainable value accrual while maintaining price stability and encouraging long-term participation.

This integrated system creates multiple reinforcing loops that drive token value, user engagement, and protocol sustainability, positioning IKIGAI as a leading protocol in the NFT and DeFi space. 