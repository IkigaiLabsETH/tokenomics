// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiStakingV2.sol";

contract IkigaiYieldExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant YIELD_MANAGER = keccak256("YIELD_MANAGER");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

    struct YieldPool {
        address rewardToken;     // Reward token
        uint256 rewardRate;      // Rewards per second
        uint256 totalStaked;     // Total staked amount
        uint256 accRewardPerShare; // Accumulated rewards per share
        bool isActive;           // Pool status
    }

    struct UserPosition {
        uint256 amount;          // Staked amount
        uint256 rewardDebt;      // Reward debt
        uint256 pendingRewards;  // Pending rewards
        uint256 lastHarvest;     // Last harvest time
        bool isCompounding;      // Auto-compound status
    }

    struct PoolConfig {
        uint256 minStake;        // Minimum stake
        uint256 harvestDelay;    // Harvest cooldown
        uint256 performanceFee;  // Performance fee
        uint256 withdrawalFee;   // Withdrawal fee
        bool requiresLock;       // Lock requirement
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiStakingV2 public staking;
    
    mapping(bytes32 => YieldPool) public yieldPools;
    mapping(bytes32 => mapping(address => UserPosition)) public userPositions;
    mapping(bytes32 => PoolConfig) public poolConfigs;
    mapping(address => bool) public supportedTokens;
    
    uint256 public constant REWARD_PRECISION = 1e12;
    uint256 public constant MAX_PERFORMANCE_FEE = 2000; // 20%
    uint256 public constant MIN_HARVEST_DELAY = 1 hours;
    
    // Events
    event PoolCreated(bytes32 indexed poolId, address rewardToken);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Harvested(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Withdrawn(bytes32 indexed poolId, address indexed user, uint256 amount);

    constructor(
        address _vault,
        address _staking
    ) {
        vault = IIkigaiVaultV2(_vault);
        staking = IIkigaiStakingV2(_staking);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createYieldPool(
        bytes32 poolId,
        address rewardToken,
        PoolConfig calldata config
    ) external onlyRole(YIELD_MANAGER) {
        require(!yieldPools[poolId].isActive, "Pool exists");
        require(supportedTokens[rewardToken], "Token not supported");
        require(config.performanceFee <= MAX_PERFORMANCE_FEE, "Fee too high");
        require(config.harvestDelay >= MIN_HARVEST_DELAY, "Delay too short");
        
        yieldPools[poolId] = YieldPool({
            rewardToken: rewardToken,
            rewardRate: 0,
            totalStaked: 0,
            accRewardPerShare: 0,
            isActive: true
        });
        
        poolConfigs[poolId] = config;
        
        emit PoolCreated(poolId, rewardToken);
    }

    // Staking operations
    function stake(
        bytes32 poolId,
        uint256 amount,
        bool autoCompound
    ) external nonReentrant whenNotPaused {
        YieldPool storage pool = yieldPools[poolId];
        require(pool.isActive, "Pool not active");
        
        PoolConfig storage config = poolConfigs[poolId];
        require(amount >= config.minStake, "Below min stake");
        
        // Update rewards
        _updatePool(poolId);
        
        // Handle existing position
        if (userPositions[poolId][msg.sender].amount > 0) {
            _harvestRewards(poolId, msg.sender);
        }
        
        // Transfer tokens
        IERC20(pool.rewardToken).transferFrom(msg.sender, address(this), amount);
        
        // Update position
        UserPosition storage position = userPositions[poolId][msg.sender];
        position.amount += amount;
        position.rewardDebt = (position.amount * pool.accRewardPerShare) / REWARD_PRECISION;
        position.isCompounding = autoCompound;
        
        pool.totalStaked += amount;
        
        emit Staked(poolId, msg.sender, amount);
    }

    // Reward harvesting
    function harvestRewards(
        bytes32 poolId
    ) external nonReentrant {
        UserPosition storage position = userPositions[poolId][msg.sender];
        require(position.amount > 0, "No position");
        
        PoolConfig storage config = poolConfigs[poolId];
        require(
            block.timestamp >= position.lastHarvest + config.harvestDelay,
            "Too soon"
        );
        
        _updatePool(poolId);
        _harvestRewards(poolId, msg.sender);
    }

    // Internal functions
    function _updatePool(
        bytes32 poolId
    ) internal {
        YieldPool storage pool = yieldPools[poolId];
        
        if (pool.totalStaked == 0) return;
        
        uint256 blockReward = _calculateBlockReward(poolId);
        pool.accRewardPerShare += (blockReward * REWARD_PRECISION) / pool.totalStaked;
    }

    function _harvestRewards(
        bytes32 poolId,
        address user
    ) internal {
        YieldPool storage pool = yieldPools[poolId];
        UserPosition storage position = userPositions[poolId][user];
        PoolConfig storage config = poolConfigs[poolId];
        
        uint256 pending = (position.amount * pool.accRewardPerShare) / REWARD_PRECISION - position.rewardDebt;
        
        if (pending > 0) {
            // Calculate fees
            uint256 fee = (pending * config.performanceFee) / 10000;
            uint256 reward = pending - fee;
            
            // Handle rewards
            if (position.isCompounding) {
                position.amount += reward;
                pool.totalStaked += reward;
            } else {
                IERC20(pool.rewardToken).transfer(user, reward);
            }
            
            // Update state
            position.rewardDebt = (position.amount * pool.accRewardPerShare) / REWARD_PRECISION;
            position.lastHarvest = block.timestamp;
            
            emit Harvested(poolId, user, reward);
        }
    }

    function _calculateBlockReward(
        bytes32 poolId
    ) internal view returns (uint256) {
        YieldPool storage pool = yieldPools[poolId];
        return pool.rewardRate * (block.timestamp - pool.lastUpdateTime);
    }

    // View functions
    function getYieldPool(
        bytes32 poolId
    ) external view returns (YieldPool memory) {
        return yieldPools[poolId];
    }

    function getUserPosition(
        bytes32 poolId,
        address user
    ) external view returns (UserPosition memory) {
        return userPositions[poolId][user];
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