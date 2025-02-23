// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiRewardsV2.sol";

contract IkigaiStakingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant STAKING_MANAGER = keccak256("STAKING_MANAGER");
    bytes32 public constant REWARDS_ROLE = keccak256("REWARDS_ROLE");

    struct StakingPool {
        address stakingToken;     // Token to stake
        uint256 totalStaked;      // Total staked amount
        uint256 rewardRate;       // Rewards per second
        uint256 lastUpdateTime;   // Last update time
        bool isActive;            // Pool status
    }

    struct UserStake {
        uint256 amount;           // Staked amount
        uint256 rewards;          // Pending rewards
        uint256 lastClaim;        // Last claim time
        uint256 lockEnd;          // Lock end time
        bool isLocked;            // Lock status
    }

    struct PoolConfig {
        uint256 minStake;         // Minimum stake
        uint256 maxStake;         // Maximum stake
        uint256 lockPeriod;       // Lock duration
        uint256 earlyWithdrawFee; // Early withdrawal fee
        bool requiresLock;        // Lock requirement
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiRewardsV2 public rewards;
    
    mapping(bytes32 => StakingPool) public stakingPools;
    mapping(bytes32 => mapping(address => UserStake)) public userStakes;
    mapping(bytes32 => PoolConfig) public poolConfigs;
    mapping(address => bool) public supportedTokens;
    
    uint256 public constant REWARD_PRECISION = 1e18;
    uint256 public constant MAX_LOCK_PERIOD = 365 days;
    uint256 public constant MAX_EARLY_FEE = 1000; // 10%
    
    // Events
    event PoolCreated(bytes32 indexed poolId, address stakingToken);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Unstaked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);

    constructor(
        address _vault,
        address _rewards
    ) {
        vault = IIkigaiVaultV2(_vault);
        rewards = IIkigaiRewardsV2(_rewards);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createPool(
        bytes32 poolId,
        address stakingToken,
        PoolConfig calldata config
    ) external onlyRole(STAKING_MANAGER) {
        require(!stakingPools[poolId].isActive, "Pool exists");
        require(supportedTokens[stakingToken], "Token not supported");
        require(config.lockPeriod <= MAX_LOCK_PERIOD, "Lock too long");
        require(config.earlyWithdrawFee <= MAX_EARLY_FEE, "Fee too high");
        
        stakingPools[poolId] = StakingPool({
            stakingToken: stakingToken,
            totalStaked: 0,
            rewardRate: 0,
            lastUpdateTime: block.timestamp,
            isActive: true
        });
        
        poolConfigs[poolId] = config;
        
        emit PoolCreated(poolId, stakingToken);
    }

    // Staking operations
    function stake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        StakingPool storage pool = stakingPools[poolId];
        require(pool.isActive, "Pool not active");
        
        PoolConfig storage config = poolConfigs[poolId];
        require(amount >= config.minStake, "Below min stake");
        
        UserStake storage userStake = userStakes[poolId][msg.sender];
        require(
            userStake.amount + amount <= config.maxStake,
            "Exceeds max stake"
        );
        
        // Update rewards
        _updateRewards(poolId, msg.sender);
        
        // Transfer tokens
        IERC20(pool.stakingToken).transferFrom(msg.sender, address(this), amount);
        
        // Update stake
        userStake.amount += amount;
        pool.totalStaked += amount;
        
        if (config.requiresLock) {
            userStake.lockEnd = block.timestamp + config.lockPeriod;
            userStake.isLocked = true;
        }
        
        emit Staked(poolId, msg.sender, amount);
    }

    // Unstaking
    function unstake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant {
        UserStake storage userStake = userStakes[poolId][msg.sender];
        require(userStake.amount >= amount, "Insufficient stake");
        
        StakingPool storage pool = stakingPools[poolId];
        PoolConfig storage config = poolConfigs[poolId];
        
        // Check lock
        if (userStake.isLocked) {
            require(block.timestamp >= userStake.lockEnd, "Still locked");
        }
        
        // Update rewards
        _updateRewards(poolId, msg.sender);
        
        // Calculate fee
        uint256 fee = 0;
        if (block.timestamp < userStake.lockEnd) {
            fee = (amount * config.earlyWithdrawFee) / 10000;
        }
        
        // Transfer tokens
        IERC20(pool.stakingToken).transfer(msg.sender, amount - fee);
        
        // Update stake
        userStake.amount -= amount;
        pool.totalStaked -= amount;
        
        if (userStake.amount == 0) {
            userStake.isLocked = false;
        }
        
        emit Unstaked(poolId, msg.sender, amount);
    }

    // Rewards claiming
    function claimRewards(
        bytes32 poolId
    ) external nonReentrant {
        UserStake storage userStake = userStakes[poolId][msg.sender];
        require(userStake.rewards > 0, "No rewards");
        
        uint256 rewards = userStake.rewards;
        userStake.rewards = 0;
        userStake.lastClaim = block.timestamp;
        
        // Transfer rewards
        rewards.transfer(msg.sender, rewards);
        
        emit RewardsClaimed(poolId, msg.sender, rewards);
    }

    // Internal functions
    function _updateRewards(
        bytes32 poolId,
        address user
    ) internal {
        StakingPool storage pool = stakingPools[poolId];
        UserStake storage userStake = userStakes[poolId][user];
        
        uint256 timeElapsed = block.timestamp - pool.lastUpdateTime;
        if (timeElapsed > 0 && pool.totalStaked > 0) {
            uint256 rewardPerToken = (timeElapsed * pool.rewardRate * REWARD_PRECISION) / pool.totalStaked;
            userStake.rewards += (userStake.amount * rewardPerToken) / REWARD_PRECISION;
        }
        
        pool.lastUpdateTime = block.timestamp;
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

    function getPoolConfig(
        bytes32 poolId
    ) external view returns (PoolConfig memory) {
        return poolConfigs[poolId];
    }

    function isTokenSupported(
        address token
    ) external view returns (bool) {
        return supportedTokens[token];
    }
} 