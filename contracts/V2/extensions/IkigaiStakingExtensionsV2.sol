// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiRewardsExtensionsV2.sol";

contract IkigaiStakingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant STAKING_MANAGER = keccak256("STAKING_MANAGER");
    bytes32 public constant REWARDS_ROLE = keccak256("REWARDS_ROLE");

    struct StakingPool {
        uint256 totalStaked;       // Total tokens staked
        uint256 rewardRate;        // Rewards per second
        uint256 lockDuration;      // Lock duration
        uint256 lastUpdateTime;    // Last update time
        bool isActive;             // Pool active status
    }

    struct UserStake {
        uint256 amount;            // Staked amount
        uint256 lockEndTime;       // Lock end time
        uint256 rewards;           // Pending rewards
        uint256 multiplier;        // Reward multiplier
        bool isLocked;             // Lock status
    }

    struct PoolStats {
        uint256 totalUsers;        // Total users
        uint256 totalRewards;      // Total rewards distributed
        uint256 avgStakeTime;      // Average stake duration
        uint256 apy;               // Current APY
        uint256 lastUpdate;        // Last update time
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiRewardsExtensionsV2 public rewards;
    IERC20 public stakingToken;
    
    mapping(bytes32 => StakingPool) public stakingPools;
    mapping(bytes32 => mapping(address => UserStake)) public userStakes;
    mapping(bytes32 => PoolStats) public poolStats;
    mapping(address => bool) public whitelistedStakers;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_STAKE = 100;
    uint256 public constant MAX_MULTIPLIER = 300; // 3x
    
    // Events
    event PoolCreated(bytes32 indexed poolId, uint256 rewardRate);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Unstaked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);

    constructor(
        address _vault,
        address _rewards,
        address _stakingToken
    ) {
        vault = IIkigaiVaultV2(_vault);
        rewards = IIkigaiRewardsExtensionsV2(_rewards);
        stakingToken = IERC20(_stakingToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createPool(
        bytes32 poolId,
        uint256 rewardRate,
        uint256 lockDuration
    ) external onlyRole(STAKING_MANAGER) {
        require(!stakingPools[poolId].isActive, "Pool exists");
        require(rewardRate > 0, "Invalid rate");
        
        stakingPools[poolId] = StakingPool({
            totalStaked: 0,
            rewardRate: rewardRate,
            lockDuration: lockDuration,
            lastUpdateTime: block.timestamp,
            isActive: true
        });
        
        emit PoolCreated(poolId, rewardRate);
    }

    // Staking operations
    function stake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount >= MIN_STAKE, "Amount too low");
        require(whitelistedStakers[msg.sender], "Not whitelisted");
        
        StakingPool storage pool = stakingPools[poolId];
        UserStake storage userStake = userStakes[poolId][msg.sender];
        
        require(pool.isActive, "Pool not active");
        
        // Transfer tokens
        stakingToken.transferFrom(msg.sender, address(this), amount);
        
        // Update user stake
        if (userStake.amount > 0) {
            _harvestRewards(poolId, msg.sender);
        }
        
        userStake.amount += amount;
        userStake.lockEndTime = block.timestamp + pool.lockDuration;
        userStake.isLocked = true;
        
        // Update pool
        pool.totalStaked += amount;
        pool.lastUpdateTime = block.timestamp;
        
        // Update stats
        _updatePoolStats(poolId);
        
        emit Staked(poolId, msg.sender, amount);
    }

    // Reward management
    function claimRewards(
        bytes32 poolId
    ) external nonReentrant {
        UserStake storage userStake = userStakes[poolId][msg.sender];
        require(userStake.amount > 0, "No stake");
        
        uint256 rewards = _calculateRewards(poolId, msg.sender);
        require(rewards > 0, "No rewards");
        
        // Reset rewards
        userStake.rewards = 0;
        
        // Transfer rewards
        stakingToken.transfer(msg.sender, rewards);
        
        emit RewardsClaimed(poolId, msg.sender, rewards);
    }

    // Internal functions
    function _harvestRewards(
        bytes32 poolId,
        address user
    ) internal {
        uint256 rewards = _calculateRewards(poolId, user);
        if (rewards > 0) {
            userStakes[poolId][user].rewards += rewards;
        }
    }

    function _calculateRewards(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        StakingPool storage pool = stakingPools[poolId];
        UserStake storage userStake = userStakes[poolId][user];
        
        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        uint256 rewardPerToken = pool.rewardRate * timeElapsed;
        
        return (userStake.amount * rewardPerToken * userStake.multiplier) / BASIS_POINTS;
    }

    function _updatePoolStats(bytes32 poolId) internal {
        PoolStats storage stats = poolStats[poolId];
        StakingPool storage pool = stakingPools[poolId];
        
        stats.totalUsers = _countStakers(poolId);
        stats.apy = _calculateAPY(poolId);
        stats.lastUpdate = block.timestamp;
    }

    function _countStakers(
        bytes32 poolId
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateAPY(
        bytes32 poolId
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    // View functions
    function getStakingPool(
        bytes32 poolId
    ) external view returns (StakingPool memory) {
        return stakingPools[poolId];
    }

    function getUserStake(
        bytes32 poolId,
        address user
    ) external view returns (UserStake memory) {
        return userStakes[poolId][user];
    }

    function getPoolStats(
        bytes32 poolId
    ) external view returns (PoolStats memory) {
        return poolStats[poolId];
    }

    function isWhitelisted(
        address staker
    ) external view returns (bool) {
        return whitelistedStakers[staker];
    }
} 