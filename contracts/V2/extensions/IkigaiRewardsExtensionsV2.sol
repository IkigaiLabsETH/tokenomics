// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiStakingV2.sol";

contract IkigaiRewardsExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant REWARDS_MANAGER = keccak256("REWARDS_MANAGER");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    struct RewardPool {
        address rewardToken;      // Reward token
        uint256 rewardRate;       // Rewards per second
        uint256 periodFinish;     // End timestamp
        uint256 lastUpdateTime;   // Last update time
        uint256 rewardPerToken;   // Accumulated rewards
    }

    struct UserRewards {
        uint256 earned;           // Earned rewards
        uint256 claimed;          // Claimed rewards
        uint256 rewardDebt;       // Reward debt
        uint256 lastUpdate;       // Last update time
        bool isActive;            // Active status
    }

    struct DistributionConfig {
        uint256 startTime;        // Start timestamp
        uint256 duration;         // Distribution duration
        uint256 totalRewards;     // Total rewards
        uint256 minStake;         // Minimum stake
        bool requiresLock;        // Lock requirement
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiStakingV2 public staking;
    
    mapping(bytes32 => RewardPool) public rewardPools;
    mapping(bytes32 => mapping(address => UserRewards)) public userRewards;
    mapping(bytes32 => DistributionConfig) public distributionConfigs;
    mapping(address => bool) public whitelistedTokens;
    
    uint256 public constant REWARD_PRECISION = 1e18;
    uint256 public constant MIN_DURATION = 7 days;
    uint256 public constant MAX_DURATION = 365 days;
    
    // Events
    event RewardPoolCreated(bytes32 indexed poolId, address rewardToken);
    event RewardsClaimed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event RewardsDistributed(bytes32 indexed poolId, uint256 amount);
    event ConfigUpdated(bytes32 indexed poolId, uint256 rewardRate);

    constructor(
        address _vault,
        address _staking
    ) {
        vault = IIkigaiVaultV2(_vault);
        staking = IIkigaiStakingV2(_staking);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createRewardPool(
        bytes32 poolId,
        address rewardToken,
        DistributionConfig calldata config
    ) external onlyRole(REWARDS_MANAGER) {
        require(!rewardPools[poolId].lastUpdateTime > 0, "Pool exists");
        require(whitelistedTokens[rewardToken], "Token not whitelisted");
        require(
            config.duration >= MIN_DURATION && 
            config.duration <= MAX_DURATION,
            "Invalid duration"
        );
        
        uint256 rewardRate = config.totalRewards / config.duration;
        
        rewardPools[poolId] = RewardPool({
            rewardToken: rewardToken,
            rewardRate: rewardRate,
            periodFinish: block.timestamp + config.duration,
            lastUpdateTime: block.timestamp,
            rewardPerToken: 0
        });
        
        distributionConfigs[poolId] = config;
        
        emit RewardPoolCreated(poolId, rewardToken);
        emit ConfigUpdated(poolId, rewardRate);
    }

    // Rewards distribution
    function distributeRewards(
        bytes32 poolId,
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        require(users.length == amounts.length, "Length mismatch");
        
        RewardPool storage pool = rewardPools[poolId];
        require(block.timestamp <= pool.periodFinish, "Distribution ended");
        
        uint256 totalAmount;
        for (uint256 i = 0; i < users.length; i++) {
            require(
                _isEligible(poolId, users[i]),
                "User not eligible"
            );
            
            UserRewards storage rewards = userRewards[poolId][users[i]];
            
            // Update rewards
            rewards.earned += amounts[i];
            rewards.lastUpdate = block.timestamp;
            rewards.isActive = true;
            
            totalAmount += amounts[i];
        }
        
        // Transfer rewards
        IERC20(pool.rewardToken).transferFrom(
            msg.sender,
            address(this),
            totalAmount
        );
        
        emit RewardsDistributed(poolId, totalAmount);
    }

    // Rewards claiming
    function claimRewards(
        bytes32 poolId
    ) external nonReentrant {
        UserRewards storage rewards = userRewards[poolId][msg.sender];
        require(rewards.isActive, "No active rewards");
        require(rewards.earned > rewards.claimed, "Nothing to claim");
        
        uint256 amount = rewards.earned - rewards.claimed;
        rewards.claimed += amount;
        
        // Transfer rewards
        RewardPool storage pool = rewardPools[poolId];
        IERC20(pool.rewardToken).transfer(msg.sender, amount);
        
        emit RewardsClaimed(poolId, msg.sender, amount);
    }

    // Internal functions
    function _isEligible(
        bytes32 poolId,
        address user
    ) internal view returns (bool) {
        DistributionConfig storage config = distributionConfigs[poolId];
        
        if (config.requiresLock) {
            // Check lock status
            // Implementation needed
        }
        
        if (config.minStake > 0) {
            uint256 stakedAmount = staking.getStakedAmount(user);
            if (stakedAmount < config.minStake) {
                return false;
            }
        }
        
        return true;
    }

    function _updateReward(
        bytes32 poolId,
        address user
    ) internal {
        RewardPool storage pool = rewardPools[poolId];
        UserRewards storage rewards = userRewards[poolId][user];
        
        pool.rewardPerToken = _getRewardPerToken(poolId);
        pool.lastUpdateTime = _lastTimeRewardApplicable(pool.periodFinish);
        
        if (user != address(0)) {
            rewards.earned = _earned(poolId, user);
            rewards.rewardDebt = pool.rewardPerToken;
        }
    }

    function _getRewardPerToken(
        bytes32 poolId
    ) internal view returns (uint256) {
        RewardPool storage pool = rewardPools[poolId];
        
        if (staking.totalSupply() == 0) {
            return pool.rewardPerToken;
        }
        
        return pool.rewardPerToken + (
            (_lastTimeRewardApplicable(pool.periodFinish) - pool.lastUpdateTime) *
            pool.rewardRate *
            REWARD_PRECISION /
            staking.totalSupply()
        );
    }

    function _lastTimeRewardApplicable(
        uint256 periodFinish
    ) internal view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function _earned(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        RewardPool storage pool = rewardPools[poolId];
        UserRewards storage rewards = userRewards[poolId][user];
        
        return (
            staking.balanceOf(user) *
            (_getRewardPerToken(poolId) - rewards.rewardDebt) /
            REWARD_PRECISION
        ) + rewards.earned;
    }

    // View functions
    function getRewardPool(
        bytes32 poolId
    ) external view returns (RewardPool memory) {
        return rewardPools[poolId];
    }

    function getUserRewards(
        bytes32 poolId,
        address user
    ) external view returns (UserRewards memory) {
        return userRewards[poolId][user];
    }

    function getDistributionConfig(
        bytes32 poolId
    ) external view returns (DistributionConfig memory) {
        return distributionConfigs[poolId];
    }

    function isTokenWhitelisted(
        address token
    ) external view returns (bool) {
        return whitelistedTokens[token];
    }
} 