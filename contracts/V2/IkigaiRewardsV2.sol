// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IkigaiTokenV2.sol";

contract IkigaiRewardsV2 is Ownable, ReentrancyGuard, Pausable {
    // Enhanced reward tiers with multipliers
    struct RewardTier {
        uint256 minAmount;      // Minimum amount for tier
        uint256 multiplier;     // Reward multiplier in basis points (100 = 1x)
        uint256 tradingBonus;   // Additional trading bonus in basis points
        uint256 stakingBonus;   // Additional staking bonus in basis points
        uint256 referralBonus;  // Additional referral bonus in basis points
    }

    // User reward tracking
    struct UserRewards {
        uint256 pendingRewards;
        uint256 lastClaimTime;
        uint256 totalClaimed;
        uint256 tradingVolume;
        uint256 stakingVolume;
        uint256 referralVolume;
        uint256 comboMultiplier;  // Increases with consecutive trades
        uint256 lastActionTime;   // For combo tracking
    }

    // Activity tracking for rate limiting
    struct ActivityLimit {
        uint256 count;
        uint256 windowStart;
        uint256 lastResetTime;
    }

    // State variables
    IkigaiTokenV2 public immutable ikigaiToken;
    address public treasury;
    
    mapping(address => UserRewards) public userRewards;
    mapping(address => ActivityLimit) public activityLimits;
    mapping(address => address) public referrers;
    
    RewardTier[] public rewardTiers;
    
    // Constants
    uint256 public constant BASE_TRADING_REWARD = 300;    // 3%
    uint256 public constant BASE_STAKING_REWARD = 200;    // 2%
    uint256 public constant BASE_REFERRAL_REWARD = 100;   // 1%
    
    uint256 public constant MAX_COMBO_MULTIPLIER = 500;   // 5x max combo
    uint256 public constant COMBO_DURATION = 24 hours;    // Time window for combos
    uint256 public constant CLAIM_COOLDOWN = 7 days;      // Minimum time between claims
    uint256 public constant RATE_LIMIT_WINDOW = 1 hours;  // Rate limiting window
    uint256 public constant MAX_ACTIONS_PER_WINDOW = 10;  // Max actions per window

    // Events
    event RewardsClaimed(address indexed user, uint256 amount);
    event TradingRewardEarned(address indexed user, uint256 amount, uint256 multiplier);
    event StakingRewardEarned(address indexed user, uint256 amount, uint256 multiplier);
    event ReferralRewardEarned(address indexed referrer, address indexed trader, uint256 amount);
    event ComboMultiplierUpdated(address indexed user, uint256 newMultiplier);
    event TierAdded(uint256 minAmount, uint256 multiplier);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        address _ikigaiToken,
        address _treasury
    ) Ownable(msg.sender) {
        ikigaiToken = IkigaiTokenV2(_ikigaiToken);
        treasury = _treasury;
        
        // Initialize reward tiers
        rewardTiers.push(RewardTier({
            minAmount: 1000 ether,    // 1,000 IKIGAI
            multiplier: 10000,        // 1x
            tradingBonus: 0,          // No bonus
            stakingBonus: 0,
            referralBonus: 0
        }));
        
        rewardTiers.push(RewardTier({
            minAmount: 5000 ether,    // 5,000 IKIGAI
            multiplier: 12500,        // 1.25x
            tradingBonus: 500,        // +5%
            stakingBonus: 300,        // +3%
            referralBonus: 200        // +2%
        }));
        
        rewardTiers.push(RewardTier({
            minAmount: 15000 ether,   // 15,000 IKIGAI
            multiplier: 15000,        // 1.5x
            tradingBonus: 1000,       // +10%
            stakingBonus: 500,        // +5%
            referralBonus: 300        // +3%
        }));
    }

    // Core reward functions
    function handleTradingReward(
        address user,
        uint256 amount
    ) external onlyOwner nonReentrant whenNotPaused {
        require(_checkRateLimit(user), "Rate limit exceeded");
        
        UserRewards storage rewards = userRewards[user];
        uint256 baseReward = (amount * BASE_TRADING_REWARD) / 10000;
        
        // Calculate final reward with multipliers
        uint256 finalReward = _calculateTotalReward(
            user,
            baseReward,
            true,   // Apply combo multiplier
            true    // Update combo
        );
        
        // Update user stats
        rewards.pendingRewards += finalReward;
        rewards.tradingVolume += amount;
        
        emit TradingRewardEarned(user, finalReward, rewards.comboMultiplier);
        
        // Handle referral rewards if applicable
        _handleReferralReward(user, amount);
    }

    function handleStakingReward(
        address user,
        uint256 amount
    ) external onlyOwner nonReentrant whenNotPaused {
        require(_checkRateLimit(user), "Rate limit exceeded");
        
        UserRewards storage rewards = userRewards[user];
        uint256 baseReward = (amount * BASE_STAKING_REWARD) / 10000;
        
        // Calculate final reward (no combo multiplier for staking)
        uint256 finalReward = _calculateTotalReward(
            user,
            baseReward,
            false,  // Don't apply combo
            false   // Don't update combo
        );
        
        // Update user stats
        rewards.pendingRewards += finalReward;
        rewards.stakingVolume += amount;
        
        emit StakingRewardEarned(user, finalReward, 0);
    }

    function claimRewards() external nonReentrant whenNotPaused {
        UserRewards storage rewards = userRewards[msg.sender];
        
        require(rewards.pendingRewards > 0, "No rewards to claim");
        require(
            block.timestamp >= rewards.lastClaimTime + CLAIM_COOLDOWN,
            "Claim cooldown active"
        );
        
        uint256 amount = rewards.pendingRewards;
        rewards.pendingRewards = 0;
        rewards.lastClaimTime = block.timestamp;
        rewards.totalClaimed += amount;
        
        require(ikigaiToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit RewardsClaimed(msg.sender, amount);
    }

    // Internal calculation functions
    function _calculateTotalReward(
        address user,
        uint256 baseReward,
        bool applyCombo,
        bool updateCombo
    ) internal returns (uint256) {
        RewardTier storage tier = _getUserTier(user);
        uint256 finalReward = baseReward;
        
        // Apply tier multiplier
        finalReward = (finalReward * tier.multiplier) / 10000;
        
        // Apply combo multiplier if applicable
        if (applyCombo) {
            UserRewards storage rewards = userRewards[user];
            if (updateCombo) {
                _updateComboMultiplier(rewards);
            }
            finalReward = (finalReward * rewards.comboMultiplier) / 10000;
        }
        
        return finalReward;
    }

    function _handleReferralReward(address user, uint256 amount) internal {
        address referrer = referrers[user];
        if (referrer == address(0)) return;
        
        uint256 baseReward = (amount * BASE_REFERRAL_REWARD) / 10000;
        RewardTier storage tier = _getUserTier(referrer);
        
        // Apply referral bonus from tier
        uint256 finalReward = (baseReward * (10000 + tier.referralBonus)) / 10000;
        
        UserRewards storage referrerRewards = userRewards[referrer];
        referrerRewards.pendingRewards += finalReward;
        referrerRewards.referralVolume += amount;
        
        emit ReferralRewardEarned(referrer, user, finalReward);
    }

    function _updateComboMultiplier(UserRewards storage rewards) internal {
        if (block.timestamp <= rewards.lastActionTime + COMBO_DURATION) {
            // Increase combo multiplier
            rewards.comboMultiplier = Math.min(
                rewards.comboMultiplier + 5000, // +50% per trade
                MAX_COMBO_MULTIPLIER
            );
        } else {
            // Reset combo if too much time has passed
            rewards.comboMultiplier = 10000; // Reset to 1x
        }
        
        rewards.lastActionTime = block.timestamp;
        emit ComboMultiplierUpdated(msg.sender, rewards.comboMultiplier);
    }

    // Rate limiting
    function _checkRateLimit(address user) internal returns (bool) {
        ActivityLimit storage limit = activityLimits[user];
        
        if (block.timestamp >= limit.windowStart + RATE_LIMIT_WINDOW) {
            limit.count = 1;
            limit.windowStart = block.timestamp;
            return true;
        }
        
        require(limit.count < MAX_ACTIONS_PER_WINDOW, "Rate limit exceeded");
        limit.count++;
        return true;
    }

    // View functions
    function _getUserTier(address user) internal view returns (RewardTier storage) {
        uint256 balance = ikigaiToken.balanceOf(user);
        
        for (uint256 i = rewardTiers.length; i > 0; i--) {
            if (balance >= rewardTiers[i-1].minAmount) {
                return rewardTiers[i-1];
            }
        }
        
        return rewardTiers[0];
    }

    function getUserRewardInfo(address user) external view returns (
        uint256 pending,
        uint256 totalClaimed,
        uint256 comboMultiplier,
        uint256 tradingVolume,
        uint256 stakingVolume,
        uint256 referralVolume,
        uint256 timeUntilNextClaim
    ) {
        UserRewards storage rewards = userRewards[user];
        
        uint256 nextClaim = rewards.lastClaimTime + CLAIM_COOLDOWN;
        timeUntilNextClaim = block.timestamp >= nextClaim ? 
            0 : nextClaim - block.timestamp;
            
        return (
            rewards.pendingRewards,
            rewards.totalClaimed,
            rewards.comboMultiplier,
            rewards.tradingVolume,
            rewards.stakingVolume,
            rewards.referralVolume,
            timeUntilNextClaim
        );
    }

    // Admin functions
    function addRewardTier(
        uint256 minAmount,
        uint256 multiplier,
        uint256 tradingBonus,
        uint256 stakingBonus,
        uint256 referralBonus
    ) external onlyOwner {
        require(multiplier <= 30000, "Max multiplier 3x");
        require(tradingBonus <= 5000, "Max trading bonus 50%");
        require(stakingBonus <= 3000, "Max staking bonus 30%");
        require(referralBonus <= 2000, "Max referral bonus 20%");
        
        rewardTiers.push(RewardTier({
            minAmount: minAmount,
            multiplier: multiplier,
            tradingBonus: tradingBonus,
            stakingBonus: stakingBonus,
            referralBonus: referralBonus
        }));
        
        emit TierAdded(minAmount, multiplier);
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "Invalid treasury");
        treasury = _treasury;
    }

    // Emergency functions
    function emergencyWithdraw() external nonReentrant {
        require(paused(), "Only when paused");
        
        UserRewards storage rewards = userRewards[msg.sender];
        require(rewards.pendingRewards > 0, "No rewards to withdraw");
        
        uint256 amount = rewards.pendingRewards;
        rewards.pendingRewards = 0;
        
        require(ikigaiToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit EmergencyWithdraw(msg.sender, amount);
    }
} 