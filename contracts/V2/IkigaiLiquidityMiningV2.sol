// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIkigaiVaultV2.sol";
import "./interfaces/IIkigaiRewardsManagerV2.sol";

contract IkigaiLiquidityMiningV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MINING_MANAGER = keccak256("MINING_MANAGER");
    bytes32 public constant REWARDS_ROLE = keccak256("REWARDS_ROLE");

    struct MiningPool {
        address lpToken;           // LP token address
        uint256 totalStaked;      // Total LP tokens staked
        uint256 rewardRate;       // Rewards per second
        uint256 lastUpdateTime;   // Last reward update
        uint256 accRewardPerShare; // Accumulated rewards per share
        bool isActive;            // Whether pool is active
    }

    struct UserStake {
        uint256 amount;           // Staked amount
        uint256 rewardDebt;       // For reward calculation
        uint256 pendingRewards;   // Unclaimed rewards
        uint256 lastStakeTime;    // Last stake timestamp
        uint256 stakingPoints;    // Points for duration
    }

    struct PoolBooster {
        uint256 durationBonus;    // Bonus for staking duration
        uint256 amountBonus;      // Bonus for stake amount
        uint256 loyaltyBonus;     // Bonus for protocol loyalty
        uint256 maxBonus;         // Maximum total bonus
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    IIkigaiVaultV2 public vault;
    IIkigaiRewardsManagerV2 public rewardsManager;
    
    mapping(bytes32 => MiningPool) public miningPools;
    mapping(bytes32 => mapping(address => UserStake)) public userStakes;
    mapping(bytes32 => PoolBooster) public poolBoosters;
    
    uint256 public constant PRECISION_FACTOR = 1e12;
    uint256 public constant MIN_STAKE_DURATION = 7 days;
    uint256 public constant MAX_BOOST_DURATION = 365 days;
    
    // Events
    event PoolCreated(bytes32 indexed poolId, address lpToken, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Unstaked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event BoosterUpdated(bytes32 indexed poolId, uint256 maxBonus);

    constructor(
        address _ikigaiToken,
        address _vault,
        address _rewardsManager
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        vault = IIkigaiVaultV2(_vault);
        rewardsManager = IIkigaiRewardsManagerV2(_rewardsManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createMiningPool(
        bytes32 poolId,
        address lpToken,
        uint256 rewardRate,
        uint256 durationBonus,
        uint256 amountBonus,
        uint256 loyaltyBonus
    ) external onlyRole(MINING_MANAGER) {
        require(lpToken != address(0), "Invalid LP token");
        require(!miningPools[poolId].isActive, "Pool exists");
        
        miningPools[poolId] = MiningPool({
            lpToken: lpToken,
            totalStaked: 0,
            rewardRate: rewardRate,
            lastUpdateTime: block.timestamp,
            accRewardPerShare: 0,
            isActive: true
        });
        
        poolBoosters[poolId] = PoolBooster({
            durationBonus: durationBonus,
            amountBonus: amountBonus,
            loyaltyBonus: loyaltyBonus,
            maxBonus: durationBonus + amountBonus + loyaltyBonus
        });
        
        emit PoolCreated(poolId, lpToken, rewardRate);
    }

    // Staking functions
    function stake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        MiningPool storage pool = miningPools[poolId];
        require(pool.isActive, "Pool not active");
        require(amount > 0, "Invalid amount");
        
        // Update pool rewards
        updatePoolRewards(poolId);
        
        // Transfer LP tokens
        IERC20(pool.lpToken).transferFrom(msg.sender, address(this), amount);
        
        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        // Calculate pending rewards before adding stake
        if (userStake.amount > 0) {
            userStake.pendingRewards += _calculateRewards(poolId, msg.sender);
        }
        
        // Update user stake
        userStake.amount += amount;
        userStake.rewardDebt = (userStake.amount * pool.accRewardPerShare) / PRECISION_FACTOR;
        userStake.lastStakeTime = block.timestamp;
        
        // Update pool
        pool.totalStaked += amount;
        
        emit Staked(poolId, msg.sender, amount);
    }

    function unstake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant {
        MiningPool storage pool = miningPools[poolId];
        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        require(amount > 0 && amount <= userStake.amount, "Invalid amount");
        require(
            block.timestamp >= userStake.lastStakeTime + MIN_STAKE_DURATION,
            "Minimum duration not met"
        );
        
        // Update pool rewards
        updatePoolRewards(poolId);
        
        // Calculate pending rewards
        uint256 pending = _calculateRewards(poolId, msg.sender);
        userStake.pendingRewards += pending;
        
        // Update user stake
        userStake.amount -= amount;
        userStake.rewardDebt = (userStake.amount * pool.accRewardPerShare) / PRECISION_FACTOR;
        
        // Update pool
        pool.totalStaked -= amount;
        
        // Transfer LP tokens back
        IERC20(pool.lpToken).transfer(msg.sender, amount);
        
        emit Unstaked(poolId, msg.sender, amount);
    }

    function claimRewards(
        bytes32 poolId
    ) external nonReentrant whenNotPaused {
        updatePoolRewards(poolId);
        
        UserStake storage userStake = userStakes[poolId][msg.sender];
        uint256 pending = _calculateRewards(poolId, msg.sender) + userStake.pendingRewards;
        
        require(pending > 0, "No rewards");
        
        // Apply boosters
        uint256 boostedRewards = _applyBoosters(poolId, pending, userStake);
        
        // Reset rewards
        userStake.pendingRewards = 0;
        userStake.rewardDebt = (userStake.amount * miningPools[poolId].accRewardPerShare) / PRECISION_FACTOR;
        
        // Transfer rewards
        require(
            ikigaiToken.transfer(msg.sender, boostedRewards),
            "Transfer failed"
        );
        
        emit RewardsClaimed(poolId, msg.sender, boostedRewards);
    }

    // Internal functions
    function updatePoolRewards(bytes32 poolId) public {
        MiningPool storage pool = miningPools[poolId];
        if (block.timestamp <= pool.lastUpdateTime) return;
        
        if (pool.totalStaked == 0) {
            pool.lastUpdateTime = block.timestamp;
            return;
        }
        
        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        uint256 rewards = timeElapsed * pool.rewardRate;
        
        pool.accRewardPerShare += (rewards * PRECISION_FACTOR) / pool.totalStaked;
        pool.lastUpdateTime = block.timestamp;
    }

    function _calculateRewards(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        UserStake storage userStake = userStakes[poolId][msg.sender];
        MiningPool storage pool = miningPools[poolId];
        
        return (userStake.amount * pool.accRewardPerShare) / PRECISION_FACTOR - userStake.rewardDebt;
    }

    function _applyBoosters(
        bytes32 poolId,
        uint256 amount,
        UserStake storage userStake
    ) internal view returns (uint256) {
        PoolBooster storage booster = poolBoosters[poolId];
        
        // Calculate duration bonus
        uint256 stakeDuration = block.timestamp - userStake.lastStakeTime;
        uint256 durationBonus = Math.min(
            (stakeDuration * booster.durationBonus) / MAX_BOOST_DURATION,
            booster.durationBonus
        );
        
        // Calculate amount bonus
        uint256 amountBonus = Math.min(
            (userStake.amount * booster.amountBonus) / (1000 * 1e18), // 1000 tokens threshold
            booster.amountBonus
        );
        
        // Apply total bonus
        uint256 totalBonus = Math.min(
            durationBonus + amountBonus + booster.loyaltyBonus,
            booster.maxBonus
        );
        
        return amount + ((amount * totalBonus) / 10000);
    }

    // View functions
    function getPoolInfo(
        bytes32 poolId
    ) external view returns (MiningPool memory) {
        return miningPools[poolId];
    }

    function getUserStakeInfo(
        bytes32 poolId,
        address user
    ) external view returns (
        UserStake memory stake,
        uint256 pendingRewards,
        uint256 boostMultiplier
    ) {
        stake = userStakes[poolId][user];
        pendingRewards = _calculateRewards(poolId, user) + stake.pendingRewards;
        boostMultiplier = _calculateBoostMultiplier(poolId, user);
        return (stake, pendingRewards, boostMultiplier);
    }

    function _calculateBoostMultiplier(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        UserStake storage userStake = userStakes[poolId][user];
        return _applyBoosters(poolId, 10000, userStake) - 10000;
    }
} 