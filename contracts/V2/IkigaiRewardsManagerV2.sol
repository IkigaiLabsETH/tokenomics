// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIkigaiVaultV2.sol";
import "./interfaces/IIkigaiStakingV2.sol";

contract IkigaiRewardsManagerV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant REWARDS_MANAGER = keccak256("REWARDS_MANAGER");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    struct RewardPool {
        uint256 totalAmount;        // Total rewards allocated
        uint256 distributed;        // Amount already distributed
        uint256 startTime;          // Pool start time
        uint256 duration;           // Pool duration
        uint256 rewardPerSecond;    // Rate of distribution
        bool isActive;              // Whether pool is active
    }

    struct UserRewards {
        uint256 pending;            // Pending rewards
        uint256 claimed;            // Total claimed
        uint256 multiplier;         // Reward multiplier
        uint256 lastUpdateTime;     // Last reward update
        uint256 rewardDebt;         // For reward calculation
    }

    struct RewardBooster {
        uint256 stakingBonus;       // Bonus for staking
        uint256 tradingBonus;       // Bonus for trading
        uint256 loyaltyBonus;       // Time-based bonus
        uint256 nftBonus;           // NFT holding bonus
        uint256 expiryTime;         // When booster expires
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    IIkigaiVaultV2 public vault;
    IIkigaiStakingV2 public staking;
    
    mapping(bytes32 => RewardPool) public rewardPools;
    mapping(address => mapping(bytes32 => UserRewards)) public userRewards;
    mapping(address => RewardBooster) public rewardBoosters;
    
    uint256 public constant PRECISION_FACTOR = 1e12;
    uint256 public constant MAX_MULTIPLIER = 500; // 5x
    uint256 public constant MIN_CLAIM_INTERVAL = 1 days;
    
    // Events
    event RewardPoolCreated(bytes32 indexed poolId, uint256 amount, uint256 duration);
    event RewardsClaimed(address indexed user, bytes32 indexed poolId, uint256 amount);
    event BoosterApplied(address indexed user, uint256 multiplier, uint256 expiry);
    event MultiplierUpdated(address indexed user, uint256 oldMultiplier, uint256 newMultiplier);

    constructor(
        address _ikigaiToken,
        address _vault,
        address _staking
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        vault = IIkigaiVaultV2(_vault);
        staking = IIkigaiStakingV2(_staking);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Core rewards functions
    function createRewardPool(
        bytes32 poolId,
        uint256 amount,
        uint256 duration
    ) external onlyRole(REWARDS_MANAGER) {
        require(amount > 0, "Invalid amount");
        require(duration >= 7 days, "Duration too short");
        require(!rewardPools[poolId].isActive, "Pool exists");
        
        // Transfer tokens to contract
        require(
            ikigaiToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        rewardPools[poolId] = RewardPool({
            totalAmount: amount,
            distributed: 0,
            startTime: block.timestamp,
            duration: duration,
            rewardPerSecond: amount / duration,
            isActive: true
        });
        
        emit RewardPoolCreated(poolId, amount, duration);
    }

    function updateUserRewards(
        address user,
        bytes32 poolId,
        uint256 amount
    ) external onlyRole(DISTRIBUTOR_ROLE) whenNotPaused {
        RewardPool storage pool = rewardPools[poolId];
        require(pool.isActive, "Pool not active");
        
        UserRewards storage rewards = userRewards[user][poolId];
        RewardBooster storage booster = rewardBoosters[user];
        
        // Calculate new rewards
        uint256 pending = calculatePendingRewards(user, poolId);
        
        // Apply boosters
        uint256 totalBonus = booster.stakingBonus + 
                            booster.tradingBonus + 
                            booster.loyaltyBonus + 
                            booster.nftBonus;
                            
        uint256 boostedAmount = amount + ((amount * totalBonus) / 10000);
        
        // Update user rewards
        rewards.pending += pending + boostedAmount;
        rewards.lastUpdateTime = block.timestamp;
        rewards.rewardDebt = rewards.pending;
        
        // Update pool stats
        pool.distributed += boostedAmount;
        
        // Check and update multiplier
        _updateMultiplier(user, poolId);
    }

    function claimRewards(
        bytes32 poolId
    ) external nonReentrant whenNotPaused {
        UserRewards storage rewards = userRewards[msg.sender][poolId];
        require(
            block.timestamp >= rewards.lastUpdateTime + MIN_CLAIM_INTERVAL,
            "Too soon to claim"
        );
        
        uint256 pending = calculatePendingRewards(msg.sender, poolId);
        require(pending > 0, "No rewards");
        
        // Reset pending rewards
        rewards.pending = 0;
        rewards.claimed += pending;
        rewards.lastUpdateTime = block.timestamp;
        
        // Transfer rewards
        require(
            ikigaiToken.transfer(msg.sender, pending),
            "Transfer failed"
        );
        
        emit RewardsClaimed(msg.sender, poolId, pending);
    }

    // Booster management
    function applyBooster(
        address user,
        uint256 stakingBonus,
        uint256 tradingBonus,
        uint256 loyaltyBonus,
        uint256 nftBonus,
        uint256 duration
    ) external onlyRole(REWARDS_MANAGER) {
        require(duration <= 90 days, "Duration too long");
        
        RewardBooster storage booster = rewardBoosters[user];
        
        // Update booster
        booster.stakingBonus = stakingBonus;
        booster.tradingBonus = tradingBonus;
        booster.loyaltyBonus = loyaltyBonus;
        booster.nftBonus = nftBonus;
        booster.expiryTime = block.timestamp + duration;
        
        emit BoosterApplied(user, stakingBonus + tradingBonus + loyaltyBonus + nftBonus, booster.expiryTime);
    }

    // Internal functions
    function _updateMultiplier(
        address user,
        bytes32 poolId
    ) internal {
        UserRewards storage rewards = userRewards[user][poolId];
        uint256 oldMultiplier = rewards.multiplier;
        
        // Calculate new multiplier based on activity
        uint256 stakingScore = calculateStakingScore(user);
        uint256 tradingScore = calculateTradingScore(user);
        uint256 loyaltyScore = calculateLoyaltyScore(user);
        
        uint256 newMultiplier = Math.min(
            (stakingScore + tradingScore + loyaltyScore),
            MAX_MULTIPLIER
        );
        
        if (newMultiplier != oldMultiplier) {
            rewards.multiplier = newMultiplier;
            emit MultiplierUpdated(user, oldMultiplier, newMultiplier);
        }
    }

    // View functions
    function calculatePendingRewards(
        address user,
        bytes32 poolId
    ) public view returns (uint256) {
        UserRewards storage rewards = userRewards[user][poolId];
        RewardPool storage pool = rewardPools[poolId];
        
        if (!pool.isActive || block.timestamp < pool.startTime) {
            return 0;
        }
        
        uint256 endTime = Math.min(block.timestamp, pool.startTime + pool.duration);
        uint256 timeElapsed = endTime - rewards.lastUpdateTime;
        
        return (timeElapsed * pool.rewardPerSecond * rewards.multiplier) / 10000;
    }

    function getBoosterInfo(
        address user
    ) external view returns (RewardBooster memory) {
        return rewardBoosters[user];
    }

    function getPoolInfo(
        bytes32 poolId
    ) external view returns (RewardPool memory) {
        return rewardPools[poolId];
    }

    // Helper functions
    function calculateStakingScore(address user) internal view returns (uint256) {
        // Implementation needed - get staking score
        return 0;
    }

    function calculateTradingScore(address user) internal view returns (uint256) {
        // Implementation needed - get trading score
        return 0;
    }

    function calculateLoyaltyScore(address user) internal view returns (uint256) {
        // Implementation needed - get loyalty score
        return 0;
    }
} 