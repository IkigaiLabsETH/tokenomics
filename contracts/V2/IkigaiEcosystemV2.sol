// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIkigaiNFTStakingV2.sol";
import "./interfaces/IIkigaiRewardsDistributorV2.sol";
import "./interfaces/IIkigaiLiquidityV2.sol";

contract IkigaiEcosystemV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ECOSYSTEM_MANAGER = keccak256("ECOSYSTEM_MANAGER");
    bytes32 public constant PARTNER_ROLE = keccak256("PARTNER_ROLE");

    struct EcosystemPartner {
        bool isActive;
        uint256 rewardShare;      // Share of ecosystem rewards (basis points)
        uint256 tradingDiscount;  // Trading fee discount (basis points)
        uint256 stakingBonus;     // Additional staking rewards (basis points)
        uint256 totalVolume;
        uint256 totalRewards;
    }

    struct UserActivity {
        uint256 tradingVolume;
        uint256 stakingVolume;
        uint256 lastActionTime;
        uint256 ecosystemPoints;
        uint256 tierLevel;
        bool isActive;
    }

    struct EcosystemTier {
        uint256 minPoints;
        uint256 tradingDiscount;
        uint256 stakingBonus;
        uint256 rewardMultiplier;
    }

    // State variables
    mapping(address => EcosystemPartner) public partners;
    mapping(address => UserActivity) public userActivity;
    mapping(uint256 => EcosystemTier) public tiers;
    
    uint256 public totalEcosystemPoints;
    uint256 public constant MAX_PARTNERS = 10;
    uint256 public constant POINTS_DECAY_RATE = 10; // 10% daily decay
    uint256 public constant MIN_ACTIVITY_INTERVAL = 1 days;
    
    // Contract references
    IIkigaiNFTStakingV2 public nftStaking;
    IIkigaiRewardsDistributorV2 public rewardsDistributor;
    IIkigaiLiquidityV2 public liquidityManager;
    IERC20 public ikigaiToken;

    // Events
    event PartnerAdded(address indexed partner, uint256 rewardShare);
    event PartnerUpdated(address indexed partner, uint256 newRewardShare);
    event UserPointsUpdated(address indexed user, uint256 points, uint256 tier);
    event EcosystemRewardsDistributed(uint256 amount, uint256 partnerCount);
    event TierUpdated(uint256 tierId, uint256 minPoints, uint256 multiplier);

    constructor(
        address _nftStaking,
        address _rewardsDistributor,
        address _liquidityManager,
        address _ikigaiToken
    ) {
        nftStaking = IIkigaiNFTStakingV2(_nftStaking);
        rewardsDistributor = IIkigaiRewardsDistributorV2(_rewardsDistributor);
        liquidityManager = IIkigaiLiquidityV2(_liquidityManager);
        ikigaiToken = IERC20(_ikigaiToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize ecosystem tiers
        tiers[0] = EcosystemTier({
            minPoints: 0,
            tradingDiscount: 0,
            stakingBonus: 0,
            rewardMultiplier: 10000 // 1x
        });
        
        tiers[1] = EcosystemTier({
            minPoints: 1000,
            tradingDiscount: 250,  // 2.5%
            stakingBonus: 500,     // 5%
            rewardMultiplier: 12500 // 1.25x
        });
        
        tiers[2] = EcosystemTier({
            minPoints: 5000,
            tradingDiscount: 500,  // 5%
            stakingBonus: 1000,    // 10%
            rewardMultiplier: 15000 // 1.5x
        });
    }

    // Ecosystem activity tracking
    function recordActivity(
        address user,
        uint256 tradingAmount,
        uint256 stakingAmount
    ) external onlyRole(PARTNER_ROLE) {
        UserActivity storage activity = userActivity[user];
        
        // Update volumes
        activity.tradingVolume += tradingAmount;
        activity.stakingVolume += stakingAmount;
        
        // Calculate points
        uint256 newPoints = calculatePoints(tradingAmount, stakingAmount);
        
        // Apply decay if inactive
        if (block.timestamp >= activity.lastActionTime + MIN_ACTIVITY_INTERVAL) {
            activity.ecosystemPoints = activity.ecosystemPoints * 
                (10000 - POINTS_DECAY_RATE) / 10000;
        }
        
        // Update points and check tier
        activity.ecosystemPoints += newPoints;
        activity.lastActionTime = block.timestamp;
        activity.isActive = true;
        
        uint256 newTier = calculateTier(activity.ecosystemPoints);
        if (newTier != activity.tierLevel) {
            activity.tierLevel = newTier;
        }
        
        totalEcosystemPoints += newPoints;
        
        emit UserPointsUpdated(user, activity.ecosystemPoints, activity.tierLevel);
    }

    // Points and tier calculation
    function calculatePoints(
        uint256 tradingAmount,
        uint256 stakingAmount
    ) public pure returns (uint256) {
        // 1 point per 1 BERA trading volume
        uint256 tradingPoints = tradingAmount / 1 ether;
        
        // 2 points per 1 IKIGAI staked
        uint256 stakingPoints = (stakingAmount * 2) / 1 ether;
        
        return tradingPoints + stakingPoints;
    }

    function calculateTier(
        uint256 points
    ) public view returns (uint256) {
        for (uint256 i = 2; i >= 0; i--) {
            if (points >= tiers[i].minPoints) {
                return i;
            }
        }
        return 0;
    }

    // Reward distribution
    function distributeEcosystemRewards() external nonReentrant whenNotPaused {
        uint256 rewardPool = ikigaiToken.balanceOf(address(this));
        require(rewardPool > 0, "No rewards to distribute");
        
        uint256 activePartners = 0;
        uint256 totalShares = 0;
        
        // Calculate total shares
        for (uint256 i = 0; i < MAX_PARTNERS; i++) {
            address partner = getPartnerAtIndex(i);
            if (partner == address(0)) break;
            
            EcosystemPartner storage p = partners[partner];
            if (p.isActive) {
                totalShares += p.rewardShare;
                activePartners++;
            }
        }
        
        require(totalShares > 0, "No active partners");
        
        // Distribute rewards
        for (uint256 i = 0; i < activePartners; i++) {
            address partner = getPartnerAtIndex(i);
            EcosystemPartner storage p = partners[partner];
            
            uint256 partnerReward = (rewardPool * p.rewardShare) / totalShares;
            if (partnerReward > 0) {
                require(
                    ikigaiToken.transfer(partner, partnerReward),
                    "Reward transfer failed"
                );
                p.totalRewards += partnerReward;
            }
        }
        
        emit EcosystemRewardsDistributed(rewardPool, activePartners);
    }

    // Partner management
    function addPartner(
        address partner,
        uint256 rewardShare,
        uint256 tradingDiscount,
        uint256 stakingBonus
    ) external onlyRole(ECOSYSTEM_MANAGER) {
        require(partner != address(0), "Invalid partner");
        require(!partners[partner].isActive, "Partner already exists");
        require(rewardShare <= 2000, "Share too high"); // Max 20%
        
        uint256 partnerCount = 0;
        for (uint256 i = 0; i < MAX_PARTNERS; i++) {
            if (getPartnerAtIndex(i) != address(0)) partnerCount++;
        }
        require(partnerCount < MAX_PARTNERS, "Max partners reached");
        
        partners[partner] = EcosystemPartner({
            isActive: true,
            rewardShare: rewardShare,
            tradingDiscount: tradingDiscount,
            stakingBonus: stakingBonus,
            totalVolume: 0,
            totalRewards: 0
        });
        
        emit PartnerAdded(partner, rewardShare);
    }

    // View functions
    function getUserInfo(
        address user
    ) external view returns (
        UserActivity memory activity,
        uint256 tradingDiscount,
        uint256 stakingBonus,
        uint256 rewardMultiplier
    ) {
        activity = userActivity[user];
        EcosystemTier storage tier = tiers[activity.tierLevel];
        
        return (
            activity,
            tier.tradingDiscount,
            tier.stakingBonus,
            tier.rewardMultiplier
        );
    }

    function getPartnerAtIndex(
        uint256 index
    ) public view returns (address) {
        // Implementation needed
        return address(0);
    }
} 