// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingV2 is ReentrancyGuard, AccessControl {
    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 lockPeriod;
        uint256 rewardMultiplier;
    }

    struct StakingTier {
        uint256 minStake;
        uint256 discount;
        uint256 minLockDuration;
        uint256 maxLockDuration;
        uint256 baseReward;
    }

    IERC20 public immutable ikigaiToken;
    
    // Lowered staking tiers
    uint256 public constant TIER1_THRESHOLD = 1_000 * 10**18; // 1,000 tokens
    uint256 public constant TIER2_THRESHOLD = 5_000 * 10**18; // 5,000 tokens
    uint256 public constant TIER3_THRESHOLD = 15_000 * 10**18; // 15,000 tokens

    // More gradual discount rates
    uint256 public constant TIER1_DISCOUNT = 5; // 5%
    uint256 public constant TIER2_DISCOUNT = 15; // 15%
    uint256 public constant TIER3_DISCOUNT = 25; // 25%

    mapping(address => Stake) public stakes;
    
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    // Add flexible lock periods
    StakingTier[] public stakingTiers = [
        StakingTier({
            minStake: 100 ether,     // 100 IKIGAI
            discount: 100,           // 1%
            minLockDuration: 1 days,
            maxLockDuration: 7 days,
            baseReward: 100          // 1% base reward
        }),
        StakingTier({
            minStake: 1000 ether,    // 1,000 IKIGAI
            discount: 500,           // 5%
            minLockDuration: 3 days,
            maxLockDuration: 14 days,
            baseReward: 200          // 2% base reward
        }),
        // ... more tiers ...
    ];

    constructor(address _ikigaiToken) {
        ikigaiToken = IERC20(_ikigaiToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function stake(uint256 amount, uint256 lockPeriod) 
        external 
        nonReentrant 
    {
        require(amount > 0, "Cannot stake 0");
        require(lockPeriod >= 7 days, "Min lock period is 7 days");
        require(lockPeriod <= 28 days, "Max lock period is 28 days");

        // Transfer tokens to contract
        require(
            ikigaiToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Calculate reward multiplier based on amount and lock period
        uint256 multiplier = calculateMultiplier(amount, lockPeriod);
        
        stakes[msg.sender] = Stake({
            amount: amount,
            timestamp: block.timestamp,
            lockPeriod: lockPeriod,
            rewardMultiplier: multiplier
        });

        emit Staked(msg.sender, amount, lockPeriod);
    }

    function calculateMultiplier(uint256 amount, uint256 lockPeriod) 
        public 
        pure 
        returns (uint256) 
    {
        uint256 baseMultiplier;
        
        if (amount >= TIER3_THRESHOLD) {
            baseMultiplier = TIER3_DISCOUNT;
        } else if (amount >= TIER2_THRESHOLD) {
            baseMultiplier = TIER2_DISCOUNT;
        } else if (amount >= TIER1_THRESHOLD) {
            baseMultiplier = TIER1_DISCOUNT;
        }

        // Additional multiplier based on lock period
        uint256 lockMultiplier = (lockPeriod * 5) / (7 days); // +5% per week
        
        return baseMultiplier + lockMultiplier;
    }

    // Add daily rewards
    function calculateDailyReward(
        uint256 amount,
        uint256 lockDuration
    ) public view returns (uint256) {
        uint256 baseReward = 0;
        uint256 durationBonus = 0;

        // Find applicable tier
        for (uint256 i = stakingTiers.length; i > 0; i--) {
            if (amount >= stakingTiers[i-1].minStake) {
                baseReward = stakingTiers[i-1].baseReward;
                break;
            }
        }

        // Calculate duration bonus (linear scaling)
        if (lockDuration >= 1 days) {
            durationBonus = (lockDuration * 100) / (30 days); // Up to 100 basis points for 30 days
        }

        return (amount * (baseReward + durationBonus)) / 10000 / 365;
    }

    // Additional functions would go here...
} 