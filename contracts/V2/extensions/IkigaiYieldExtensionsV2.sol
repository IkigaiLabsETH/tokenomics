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
        address rewardToken;     // Reward token address
        uint256 rewardRate;      // Rewards per second
        uint256 totalStaked;     // Total staked amount
        uint256 lastUpdate;      // Last update time
        bool isActive;           // Pool status
    }

    struct UserPosition {
        uint256 stakedAmount;    // User staked amount
        uint256 rewardDebt;      // Reward debt
        uint256 pendingRewards;  // Pending rewards
        uint256 lastClaim;       // Last claim time
        bool isActive;           // Position status
    }

    struct PoolStats {
        uint256 totalUsers;      // Total users
        uint256 totalRewards;    // Total rewards distributed
        uint256 avgAPY;         // Average APY
        uint256 tvl;            // Total value locked
        uint256 lastUpdate;     // Last update time
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiStakingV2 public staking;
    
    mapping(bytes32 => YieldPool) public yieldPools;
    mapping(bytes32 => mapping(address => UserPosition)) public userPositions;
    mapping(bytes32 => PoolStats) public poolStats;
    mapping(address => bool) public supportedTokens;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_STAKE = 100;
    uint256 public constant CLAIM_INTERVAL = 1 days;
    
    // Events
    event PoolCreated(bytes32 indexed poolId, address rewardToken);
    event Staked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Unstaked(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardsClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);

    constructor(
        address _vault,
        address _staking
    ) {
        vault = IIkigaiVaultV2(_vault);
        staking = IIkigaiStakingV2(_staking);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createPool(
        bytes32 poolId,
        address rewardToken,
        uint256 rewardRate
    ) external onlyRole(YIELD_MANAGER) {
        require(!yieldPools[poolId].isActive, "Pool exists");
        require(rewardToken != address(0), "Invalid token");
        require(rewardRate > 0, "Invalid rate");
        
        yieldPools[poolId] = YieldPool({
            rewardToken: rewardToken,
            rewardRate: rewardRate,
            totalStaked: 0,
            lastUpdate: block.timestamp,
            isActive: true
        });
        
        supportedTokens[rewardToken] = true;
        
        emit PoolCreated(poolId, rewardToken);
    }

    // Staking operations
    function stake(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount >= MIN_STAKE, "Amount too small");
        
        YieldPool storage pool = yieldPools[poolId];
        require(pool.isActive, "Pool not active");
        
        UserPosition storage position = userPositions[poolId][msg.sender];
        
        // Update rewards
        if (position.isActive) {
            _harvestRewards(poolId, msg.sender);
        }
        
        // Transfer tokens
        IERC20(pool.rewardToken).transferFrom(msg.sender, address(this), amount);
        
        // Update position
        position.stakedAmount += amount;
        position.rewardDebt = _calculateRewardDebt(poolId, position.stakedAmount);
        position.isActive = true;
        
        // Update pool
        pool.totalStaked += amount;
        pool.lastUpdate = block.timestamp;
        
        // Update stats
        if (!position.isActive) {
            poolStats[poolId].totalUsers++;
        }
        poolStats[poolId].tvl += amount;
        
        emit Staked(poolId, msg.sender, amount);
    }

    // Reward harvesting
    function harvestRewards(
        bytes32 poolId
    ) external nonReentrant {
        UserPosition storage position = userPositions[poolId][msg.sender];
        require(position.isActive, "No active position");
        require(
            block.timestamp >= position.lastClaim + CLAIM_INTERVAL,
            "Too frequent"
        );
        
        uint256 rewards = _harvestRewards(poolId, msg.sender);
        require(rewards > 0, "No rewards");
        
        // Transfer rewards
        YieldPool storage pool = yieldPools[poolId];
        IERC20(pool.rewardToken).transfer(msg.sender, rewards);
        
        // Update stats
        poolStats[poolId].totalRewards += rewards;
        
        emit RewardsClaimed(poolId, msg.sender, rewards);
    }

    // Internal functions
    function _harvestRewards(
        bytes32 poolId,
        address user
    ) internal returns (uint256) {
        UserPosition storage position = userPositions[poolId][msg.sender];
        
        uint256 pending = _calculatePendingRewards(poolId, user);
        if (pending > 0) {
            position.pendingRewards += pending;
        }
        
        position.lastClaim = block.timestamp;
        position.rewardDebt = _calculateRewardDebt(poolId, position.stakedAmount);
        
        return pending;
    }

    function _calculatePendingRewards(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        YieldPool storage pool = yieldPools[poolId];
        UserPosition storage position = userPositions[poolId][user];
        
        uint256 timeElapsed = block.timestamp - pool.lastUpdate;
        uint256 rewardPerToken = pool.rewardRate * timeElapsed;
        
        return (position.stakedAmount * rewardPerToken) / pool.totalStaked;
    }

    function _calculateRewardDebt(
        bytes32 poolId,
        uint256 amount
    ) internal view returns (uint256) {
        YieldPool storage pool = yieldPools[poolId];
        return (amount * pool.rewardRate) / pool.totalStaked;
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

    function getPoolStats(
        bytes32 poolId
    ) external view returns (PoolStats memory) {
        return poolStats[poolId];
    }

    function isTokenSupported(
        address token
    ) external view returns (bool) {
        return supportedTokens[token];
    }
} 