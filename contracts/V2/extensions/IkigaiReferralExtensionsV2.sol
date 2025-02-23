// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";

contract IkigaiReferralExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant REFERRAL_MANAGER = keccak256("REFERRAL_MANAGER");
    bytes32 public constant REWARDS_ROLE = keccak256("REWARDS_ROLE");

    struct ReferralProgram {
        uint256 rewardRate;        // Reward percentage
        uint256 minVolume;         // Minimum volume required
        uint256 maxReward;         // Maximum reward per referral
        uint256 duration;          // Program duration
        bool isActive;             // Program status
    }

    struct ReferralStats {
        uint256 totalReferrals;    // Total referrals
        uint256 activeReferrals;   // Active referrals
        uint256 totalVolume;       // Total referral volume
        uint256 totalRewards;      // Total rewards earned
        uint256 lastUpdate;        // Last update time
    }

    struct UserReferral {
        address referrer;          // Referrer address
        uint256 joinTime;          // Join timestamp
        uint256 volume;            // Trading volume
        uint256 rewards;           // Earned rewards
        bool isActive;             // Referral status
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiMarketplaceV2 public marketplace;
    IERC20 public rewardsToken;
    
    mapping(bytes32 => ReferralProgram) public referralPrograms;
    mapping(address => ReferralStats) public referralStats;
    mapping(address => UserReferral) public userReferrals;
    mapping(address => bool) public whitelistedReferrers;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_REWARD_RATE = 5000; // 50%
    uint256 public constant MIN_REFERRAL_AGE = 7 days;
    
    // Events
    event ProgramCreated(bytes32 indexed programId, uint256 rewardRate);
    event ReferralRegistered(address indexed referrer, address indexed referee);
    event RewardsClaimed(address indexed user, uint256 amount);
    event VolumeUpdated(address indexed user, uint256 volume);

    constructor(
        address _vault,
        address _marketplace,
        address _rewardsToken
    ) {
        vault = IIkigaiVaultV2(_vault);
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        rewardsToken = IERC20(_rewardsToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Program management
    function createProgram(
        bytes32 programId,
        ReferralProgram calldata program
    ) external onlyRole(REFERRAL_MANAGER) {
        require(!referralPrograms[programId].isActive, "Program exists");
        require(program.rewardRate <= MAX_REWARD_RATE, "Rate too high");
        require(program.duration > 0, "Invalid duration");
        
        referralPrograms[programId] = program;
        
        emit ProgramCreated(programId, program.rewardRate);
    }

    // Referral registration
    function registerReferral(
        bytes32 programId,
        address referrer
    ) external nonReentrant whenNotPaused {
        require(whitelistedReferrers[referrer], "Invalid referrer");
        require(userReferrals[msg.sender].referrer == address(0), "Already referred");
        
        ReferralProgram storage program = referralPrograms[programId];
        require(program.isActive, "Program not active");
        
        // Create referral
        userReferrals[msg.sender] = UserReferral({
            referrer: referrer,
            joinTime: block.timestamp,
            volume: 0,
            rewards: 0,
            isActive: true
        });
        
        // Update stats
        referralStats[referrer].totalReferrals++;
        referralStats[referrer].activeReferrals++;
        
        emit ReferralRegistered(referrer, msg.sender);
    }

    // Volume tracking
    function updateVolume(
        address user,
        uint256 volume
    ) external onlyRole(REWARDS_ROLE) {
        UserReferral storage referral = userReferrals[user];
        require(referral.isActive, "Referral not active");
        
        // Update volume
        referral.volume += volume;
        
        // Update referrer stats
        referralStats[referral.referrer].totalVolume += volume;
        
        // Calculate rewards
        uint256 rewards = _calculateRewards(user, volume);
        if (rewards > 0) {
            referral.rewards += rewards;
            referralStats[referral.referrer].totalRewards += rewards;
        }
        
        emit VolumeUpdated(user, volume);
    }

    // Rewards claiming
    function claimRewards(
        address user
    ) external nonReentrant {
        UserReferral storage referral = userReferrals[user];
        require(referral.rewards > 0, "No rewards");
        require(
            block.timestamp >= referral.joinTime + MIN_REFERRAL_AGE,
            "Too early"
        );
        
        uint256 rewards = referral.rewards;
        referral.rewards = 0;
        
        // Transfer rewards
        require(
            rewardsToken.transfer(user, rewards),
            "Transfer failed"
        );
        
        emit RewardsClaimed(user, rewards);
    }

    // Internal functions
    function _calculateRewards(
        address user,
        uint256 volume
    ) internal view returns (uint256) {
        UserReferral storage referral = userReferrals[user];
        bytes32 programId = _getUserProgram(user);
        ReferralProgram storage program = referralPrograms[programId];
        
        if (referral.volume < program.minVolume) {
            return 0;
        }
        
        uint256 reward = (volume * program.rewardRate) / BASIS_POINTS;
        return reward > program.maxReward ? program.maxReward : reward;
    }

    function _getUserProgram(
        address user
    ) internal view returns (bytes32) {
        // Implementation needed
        return bytes32(0);
    }

    // View functions
    function getReferralProgram(
        bytes32 programId
    ) external view returns (ReferralProgram memory) {
        return referralPrograms[programId];
    }

    function getReferralStats(
        address referrer
    ) external view returns (ReferralStats memory) {
        return referralStats[referrer];
    }

    function getUserReferral(
        address user
    ) external view returns (UserReferral memory) {
        return userReferrals[user];
    }

    function isReferrerWhitelisted(
        address referrer
    ) external view returns (bool) {
        return whitelistedReferrers[referrer];
    }
} 