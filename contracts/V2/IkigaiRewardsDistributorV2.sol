// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IkigaiRewardsDistributorV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    struct RewardConfig {
        uint256 baseRate;          // Base reward rate
        uint256 maxMultiplier;     // Maximum reward multiplier
        uint256 minAmount;         // Minimum amount for rewards
        uint256 maxAmount;         // Maximum amount for rewards
        uint256 cooldownPeriod;    // Time between claims
        bool requiresStaking;      // Whether staking is required
    }

    struct UserRewards {
        uint256 pending;
        uint256 claimed;
        uint256 lastClaimTime;
        uint256 multiplier;
        uint256 stakingBonus;
        uint256 tradingBonus;
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    mapping(address => UserRewards) public userRewards;
    mapping(bytes32 => RewardConfig) public rewardConfigs;
    
    // Events
    event RewardEarned(address indexed user, bytes32 rewardType, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event ConfigUpdated(bytes32 rewardType, string parameter, uint256 value);
    event MultiplierUpdated(address indexed user, uint256 newMultiplier);

    constructor(address _ikigaiToken) {
        ikigaiToken = IERC20(_ikigaiToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize reward configs
        rewardConfigs["TRADING"] = RewardConfig({
            baseRate: 300,         // 3%
            maxMultiplier: 500,    // 5x
            minAmount: 1 ether,    // 1 BERA
            maxAmount: 1000 ether, // 1000 BERA
            cooldownPeriod: 1 days,
            requiresStaking: false
        });
        
        rewardConfigs["STAKING"] = RewardConfig({
            baseRate: 200,         // 2%
            maxMultiplier: 300,    // 3x
            minAmount: 100 ether,  // 100 IKIGAI
            maxAmount: 100000 ether, // 100k IKIGAI
            cooldownPeriod: 7 days,
            requiresStaking: true
        });
    }

    // Core reward functions
    function calculateReward(
        address user,
        bytes32 rewardType,
        uint256 amount
    ) public view returns (uint256) {
        RewardConfig storage config = rewardConfigs[rewardType];
        require(amount >= config.minAmount, "Amount too small");
        require(amount <= config.maxAmount, "Amount too large");

        UserRewards storage rewards = userRewards[user];
        
        uint256 baseReward = (amount * config.baseRate) / 10000;
        uint256 multiplier = Math.min(
            rewards.multiplier + rewards.stakingBonus + rewards.tradingBonus,
            config.maxMultiplier
        );
        
        return (baseReward * multiplier) / 10000;
    }

    function distributeReward(
        address user,
        bytes32 rewardType,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DISTRIBUTOR_ROLE) {
        uint256 reward = calculateReward(user, rewardType, amount);
        UserRewards storage rewards = userRewards[user];
        
        rewards.pending += reward;
        emit RewardEarned(user, rewardType, reward);
        
        _updateMultipliers(user, rewardType, amount);
    }

    function claimRewards() external nonReentrant whenNotPaused {
        UserRewards storage rewards = userRewards[msg.sender];
        require(rewards.pending > 0, "No rewards to claim");
        require(
            block.timestamp >= rewards.lastClaimTime + rewardConfigs["STAKING"].cooldownPeriod,
            "Cooldown active"
        );

        uint256 amount = rewards.pending;
        rewards.pending = 0;
        rewards.claimed += amount;
        rewards.lastClaimTime = block.timestamp;

        require(ikigaiToken.transfer(msg.sender, amount), "Transfer failed");
        emit RewardClaimed(msg.sender, amount);
    }

    // Multiplier management
    function _updateMultipliers(
        address user,
        bytes32 rewardType,
        uint256 amount
    ) internal {
        UserRewards storage rewards = userRewards[user];
        
        if (rewardType == "TRADING") {
            rewards.tradingBonus = Math.min(
                rewards.tradingBonus + 1000, // +10% per trade
                5000 // Max 50% bonus
            );
        } else if (rewardType == "STAKING") {
            rewards.stakingBonus = Math.min(
                rewards.stakingBonus + 500, // +5% per stake
                3000 // Max 30% bonus
            );
        }

        emit MultiplierUpdated(user, rewards.multiplier);
    }

    // Admin functions
    function updateRewardConfig(
        bytes32 rewardType,
        string memory parameter,
        uint256 value
    ) external onlyRole(MANAGER_ROLE) {
        RewardConfig storage config = rewardConfigs[rewardType];
        
        if (keccak256(bytes(parameter)) == keccak256(bytes("baseRate"))) {
            require(value <= 1000, "Rate too high"); // Max 10%
            config.baseRate = value;
        } // ... etc

        emit ConfigUpdated(rewardType, parameter, value);
    }

    // View functions
    function getUserRewardInfo(
        address user
    ) external view returns (
        uint256 pending,
        uint256 claimed,
        uint256 multiplier,
        uint256 timeUntilClaim
    ) {
        UserRewards storage rewards = userRewards[user];
        uint256 nextClaim = rewards.lastClaimTime + rewardConfigs["STAKING"].cooldownPeriod;
        
        return (
            rewards.pending,
            rewards.claimed,
            rewards.multiplier + rewards.stakingBonus + rewards.tradingBonus,
            block.timestamp >= nextClaim ? 0 : nextClaim - block.timestamp
        );
    }
} 