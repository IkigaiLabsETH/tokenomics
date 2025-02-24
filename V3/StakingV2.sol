// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IBuybackEngine.sol";

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

    // Add buyback engine reference
    IBuybackEngine public buybackEngine;

    // Add buyback configuration
    uint256 public constant STAKING_BUYBACK_SHARE = 2500; // 25% (increased from 20%)

    // Add whitelist for fee exemption
    mapping(address => bool) public feeExempt;

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
    event FeeExemptionUpdated(address indexed account, bool exempt);
    event EmergencyRecovery(address indexed token, uint256 amount);

    constructor(
        address _ikigaiToken,
        address _buybackEngine,
        address _admin
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        buybackEngine = IBuybackEngine(_buybackEngine);
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
        require(amount <= ikigaiToken.balanceOf(msg.sender), "Insufficient balance");
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
        
        // Calculate and send buyback allocation (skip for exempt addresses)
        if (!feeExempt[msg.sender]) {
            uint256 buybackAmount = (amount * STAKING_BUYBACK_SHARE) / 10000;
            if (buybackAmount > 0) {
                ikigaiToken.safeApprove(address(buybackEngine), buybackAmount);
                buybackEngine.collectRevenue(keccak256("STAKING_FEES"), buybackAmount);
            }
        }

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

    // Function to update fee exemption
    function setFeeExemption(address account, bool exempt) external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Caller is not operator");
        feeExempt[account] = exempt;
        emit FeeExemptionUpdated(account, exempt);
    }

    // Add emergency token recovery
    function emergencyTokenRecovery(address token, uint256 amount) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Must be admin");
        require(paused(), "Contract not paused");
        require(token != address(ikigaiToken) || 
                IERC20(token).balanceOf(address(this)) > totalStaked, 
                "Cannot withdraw staked tokens");
        
        IERC20(token).safeTransfer(msg.sender, amount);
        emit EmergencyRecovery(token, amount);
    }
} 