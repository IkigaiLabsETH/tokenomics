// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StakingV2 is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Staking token
    IERC20 public immutable ikigaiToken;

    // Tier thresholds
    uint256 public constant TIER1_THRESHOLD = 1_000 * 10**18; // 1,000 IKIGAI
    uint256 public constant TIER2_THRESHOLD = 5_000 * 10**18; // 5,000 IKIGAI
    uint256 public constant TIER3_THRESHOLD = 15_000 * 10**18; // 15,000 IKIGAI

    // Tier discounts (in basis points, 100 = 1%)
    uint256 public constant TIER1_DISCOUNT = 500;  // 5%
    uint256 public constant TIER2_DISCOUNT = 1500; // 15%
    uint256 public constant TIER3_DISCOUNT = 2500; // 25%

    // Lock periods
    uint256 public constant MIN_LOCK_PERIOD = 7 days;
    uint256 public constant MAX_LOCK_PERIOD = 28 days;
    uint256 public constant WEEKLY_BONUS = 500; // 5% per week

    // Base staking rate (in basis points)
    uint256 public constant BASE_RATE = 200; // 2%

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 lockPeriod;
        uint256 tier;
        uint256 rewards;
        bool active;
    }

    // Staker info
    mapping(address => Stake) public stakes;
    
    // Total staked amount
    uint256 public totalStaked;

    // Events
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);
    event TierUpgraded(address indexed user, uint256 oldTier, uint256 newTier);

    constructor(address _ikigaiToken, address _admin) {
        ikigaiToken = IERC20(_ikigaiToken);
        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);
    }

    // Get user's tier based on stake amount
    function getUserTier(uint256 amount) public pure returns (uint256) {
        if (amount >= TIER3_THRESHOLD) return 3;
        if (amount >= TIER2_THRESHOLD) return 2;
        if (amount >= TIER1_THRESHOLD) return 1;
        return 0;
    }

    // Calculate lock period multiplier
    function getLockMultiplier(uint256 lockPeriod) public pure returns (uint256) {
        uint256 weeks = lockPeriod / 1 weeks;
        return 10000 + (weeks * WEEKLY_BONUS); // Base 100% + weekly bonus
    }

    // Calculate tier multiplier
    function getTierMultiplier(uint256 tier) public pure returns (uint256) {
        if (tier == 3) return 10000 + TIER3_DISCOUNT;
        if (tier == 2) return 10000 + TIER2_DISCOUNT;
        if (tier == 1) return 10000 + TIER1_DISCOUNT;
        return 10000;
    }

    // Stake tokens
    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant whenNotPaused {
        require(amount > 0, "Cannot stake 0");
        require(lockPeriod >= MIN_LOCK_PERIOD, "Lock period too short");
        require(lockPeriod <= MAX_LOCK_PERIOD, "Lock period too long");

        Stake storage userStake = stakes[msg.sender];
        require(!userStake.active, "Already staking");

        uint256 tier = getUserTier(amount);
        
        ikigaiToken.safeTransferFrom(msg.sender, address(this), amount);
        
        userStake.amount = amount;
        userStake.startTime = block.timestamp;
        userStake.lockPeriod = lockPeriod;
        userStake.tier = tier;
        userStake.active = true;
        userStake.rewards = 0;

        totalStaked += amount;
        
        emit Staked(msg.sender, amount, lockPeriod);
        if (tier > 0) {
            emit TierUpgraded(msg.sender, 0, tier);
        }
    }

    // Calculate rewards for a stake
    function calculateRewards(Stake memory _stake) public view returns (uint256) {
        if (!_stake.active) return 0;
        
        uint256 timeStaked = block.timestamp - _stake.startTime;
        if (timeStaked > _stake.lockPeriod) {
            timeStaked = _stake.lockPeriod;
        }

        uint256 baseReward = (_stake.amount * BASE_RATE * timeStaked) / (365 days * 10000);
        uint256 tierMultiplier = getTierMultiplier(_stake.tier);
        uint256 lockMultiplier = getLockMultiplier(_stake.lockPeriod);
        
        return (baseReward * tierMultiplier * lockMultiplier) / (10000 * 10000);
    }

    // Unstake tokens and claim rewards
    function unstake() external nonReentrant {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.active, "No active stake");
        require(block.timestamp >= userStake.startTime + userStake.lockPeriod, "Lock period not ended");

        uint256 rewards = calculateRewards(userStake);
        uint256 amount = userStake.amount;

        userStake.active = false;
        totalStaked -= amount;

        // Transfer staked tokens back
        ikigaiToken.safeTransfer(msg.sender, amount);
        
        // Transfer rewards if any
        if (rewards > 0) {
            ikigaiToken.safeTransfer(msg.sender, rewards);
            emit RewardsClaimed(msg.sender, rewards);
        }

        emit Unstaked(msg.sender, amount, rewards);
    }

    // View functions
    function getStakeInfo(address user) external view returns (
        uint256 amount,
        uint256 startTime,
        uint256 lockPeriod,
        uint256 tier,
        uint256 rewards,
        bool active
    ) {
        Stake memory stake = stakes[user];
        return (
            stake.amount,
            stake.startTime,
            stake.lockPeriod,
            stake.tier,
            calculateRewards(stake),
            stake.active
        );
    }

    // Emergency functions
    function pause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not an operator");
        _pause();
    }

    function unpause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not an operator");
        _unpause();
    }

    // Emergency withdraw
    function emergencyWithdraw() external nonReentrant {
        require(paused(), "Contract not paused");
        Stake storage userStake = stakes[msg.sender];
        require(userStake.active, "No active stake");

        uint256 amount = userStake.amount;
        userStake.active = false;
        totalStaked -= amount;

        ikigaiToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount, 0);
    }
} 