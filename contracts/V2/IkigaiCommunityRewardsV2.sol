// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract IkigaiCommunityRewardsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant COMMUNITY_MANAGER = keccak256("COMMUNITY_MANAGER");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    struct ContributionTier {
        uint256 minPoints;         // Minimum points required
        uint256 rewardMultiplier;  // Reward multiplier (basis points)
        uint256 maxRewardPerDay;   // Maximum daily rewards
        uint256 cooldownPeriod;    // Time between rewards
        bool requiresValidation;   // Whether validation is required
    }

    struct UserProfile {
        uint256 totalPoints;       // Total contribution points
        uint256 currentTier;       // Current tier level
        uint256 totalRewards;      // Total rewards earned
        uint256 lastRewardTime;    // Last reward claim
        uint256 dailyRewards;      // Rewards claimed today
        uint256 reputationScore;   // User reputation
    }

    struct Activity {
        uint256 basePoints;        // Base points for activity
        uint256 maxDaily;          // Maximum daily submissions
        uint256 validationThreshold; // Required validations
        bool isActive;             // Whether activity is enabled
        bool requiresProof;        // Whether proof is required
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    
    mapping(uint256 => ContributionTier) public tiers;
    mapping(address => UserProfile) public userProfiles;
    mapping(bytes32 => Activity) public activities;
    mapping(address => mapping(bytes32 => uint256)) public dailySubmissions;
    mapping(bytes32 => mapping(uint256 => uint256)) public validationCount;
    
    uint256 public constant MAX_TIER = 5;
    uint256 public constant DAILY_RESET_PERIOD = 1 days;
    uint256 public constant MIN_REPUTATION = 100;
    
    // Events
    event ContributionSubmitted(
        address indexed user,
        bytes32 indexed activityType,
        uint256 points,
        uint256 submissionId
    );
    event ContributionValidated(
        bytes32 indexed activityType,
        uint256 indexed submissionId,
        address validator
    );
    event RewardsClaimed(address indexed user, uint256 amount);
    event TierUpdated(address indexed user, uint256 oldTier, uint256 newTier);

    constructor(address _ikigaiToken) {
        ikigaiToken = IERC20(_ikigaiToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize tiers
        tiers[1] = ContributionTier({
            minPoints: 0,
            rewardMultiplier: 10000, // 1x
            maxRewardPerDay: 100 * 1e18,
            cooldownPeriod: 1 days,
            requiresValidation: false
        });
        
        tiers[2] = ContributionTier({
            minPoints: 1000,
            rewardMultiplier: 12500, // 1.25x
            maxRewardPerDay: 250 * 1e18,
            cooldownPeriod: 12 hours,
            requiresValidation: false
        });
        
        tiers[3] = ContributionTier({
            minPoints: 5000,
            rewardMultiplier: 15000, // 1.5x
            maxRewardPerDay: 500 * 1e18,
            cooldownPeriod: 6 hours,
            requiresValidation: true
        });
    }

    // Core contribution functions
    function submitContribution(
        bytes32 activityType,
        string calldata proof,
        uint256 submissionId
    ) external nonReentrant whenNotPaused {
        Activity storage activity = activities[activityType];
        require(activity.isActive, "Activity not active");
        
        // Check daily limit
        uint256 today = block.timestamp / DAILY_RESET_PERIOD;
        require(
            dailySubmissions[msg.sender][activityType] < activity.maxDaily,
            "Daily limit reached"
        );
        
        // Validate proof if required
        if (activity.requiresProof) {
            require(bytes(proof).length > 0, "Proof required");
        }
        
        // Update submission count
        dailySubmissions[msg.sender][activityType]++;
        
        // Award points immediately if no validation required
        if (!activity.requiresProof) {
            _awardPoints(msg.sender, activity.basePoints);
        }
        
        emit ContributionSubmitted(
            msg.sender,
            activityType,
            activity.basePoints,
            submissionId
        );
    }

    function validateContribution(
        bytes32 activityType,
        uint256 submissionId
    ) external onlyRole(VALIDATOR_ROLE) {
        Activity storage activity = activities[activityType];
        require(activity.requiresProof, "Validation not required");
        
        validationCount[activityType][submissionId]++;
        
        // Award points if threshold reached
        if (validationCount[activityType][submissionId] >= activity.validationThreshold) {
            _awardPoints(msg.sender, activity.basePoints);
        }
        
        emit ContributionValidated(activityType, submissionId, msg.sender);
    }

    function claimRewards() external nonReentrant whenNotPaused {
        UserProfile storage profile = userProfiles[msg.sender];
        ContributionTier storage tier = tiers[profile.currentTier];
        
        require(
            block.timestamp >= profile.lastRewardTime + tier.cooldownPeriod,
            "Cooldown active"
        );
        require(profile.reputationScore >= MIN_REPUTATION, "Reputation too low");
        
        // Calculate rewards
        uint256 baseReward = calculateBaseReward(msg.sender);
        uint256 multipliedReward = (baseReward * tier.rewardMultiplier) / 10000;
        
        // Check daily limit
        require(
            profile.dailyRewards + multipliedReward <= tier.maxRewardPerDay,
            "Daily limit exceeded"
        );
        
        // Update user profile
        profile.totalRewards += multipliedReward;
        profile.dailyRewards += multipliedReward;
        profile.lastRewardTime = block.timestamp;
        
        // Transfer rewards
        require(
            ikigaiToken.transfer(msg.sender, multipliedReward),
            "Transfer failed"
        );
        
        emit RewardsClaimed(msg.sender, multipliedReward);
    }

    // Internal functions
    function _awardPoints(address user, uint256 points) internal {
        UserProfile storage profile = userProfiles[user];
        uint256 oldTier = profile.currentTier;
        
        // Update points
        profile.totalPoints += points;
        
        // Check for tier upgrade
        uint256 newTier = calculateTier(profile.totalPoints);
        if (newTier != oldTier) {
            profile.currentTier = newTier;
            emit TierUpdated(user, oldTier, newTier);
        }
    }

    function calculateTier(uint256 points) public view returns (uint256) {
        for (uint256 i = MAX_TIER; i > 0; i--) {
            if (points >= tiers[i].minPoints) {
                return i;
            }
        }
        return 1;
    }

    function calculateBaseReward(address user) public view returns (uint256) {
        UserProfile storage profile = userProfiles[user];
        return (profile.totalPoints * 1e18) / 10000; // 0.01 tokens per point
    }

    // Activity management
    function addActivity(
        bytes32 activityType,
        uint256 basePoints,
        uint256 maxDaily,
        uint256 validationThreshold,
        bool requiresProof
    ) external onlyRole(COMMUNITY_MANAGER) {
        require(!activities[activityType].isActive, "Activity exists");
        
        activities[activityType] = Activity({
            basePoints: basePoints,
            maxDaily: maxDaily,
            validationThreshold: validationThreshold,
            isActive: true,
            requiresProof: requiresProof
        });
    }

    // View functions
    function getUserProfile(
        address user
    ) external view returns (UserProfile memory) {
        return userProfiles[user];
    }

    function getActivityInfo(
        bytes32 activityType
    ) external view returns (Activity memory) {
        return activities[activityType];
    }

    function getDailySubmissions(
        address user,
        bytes32 activityType
    ) external view returns (uint256) {
        uint256 today = block.timestamp / DAILY_RESET_PERIOD;
        return dailySubmissions[user][activityType];
    }
} 