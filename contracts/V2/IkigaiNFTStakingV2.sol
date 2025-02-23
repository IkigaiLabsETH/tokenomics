// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IkigaiTokenV2.sol";

contract IkigaiNFTStakingV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REWARDS_ROLE = keccak256("REWARDS_ROLE");

    struct StakingTier {
        uint256 minStakeTime;    // Minimum time to earn rewards
        uint256 rewardRate;      // Rewards per day (basis points)
        uint256 boostMultiplier; // Boost for longer staking
        uint256 maxBoost;        // Maximum boost possible
    }

    struct NFTStake {
        uint256 tokenId;
        uint256 startTime;
        uint256 lastClaimTime;
        uint256 accumulatedRewards;
        bool isActive;
    }

    struct Collection {
        bool isSupported;
        uint256 stakingTier;
        uint256 totalStaked;
        uint256 rewardsDistributed;
        uint256 lastUpdateTime;
    }

    // State variables
    IkigaiTokenV2 public immutable ikigaiToken;
    mapping(address => Collection) public collections;
    mapping(address => mapping(uint256 => NFTStake)) public stakes;
    mapping(address => uint256[]) public userStakedTokens;
    StakingTier[] public stakingTiers;
    
    // Staking limits
    uint256 public constant MAX_STAKE_PER_USER = 50;
    uint256 public constant MIN_STAKE_DURATION = 7 days;
    uint256 public constant MAX_BOOST_DURATION = 90 days;
    
    // Events
    event NFTStaked(address indexed collection, uint256 indexed tokenId, address indexed staker);
    event NFTUnstaked(address indexed collection, uint256 indexed tokenId, address indexed staker);
    event RewardsClaimed(address indexed staker, uint256 amount);
    event CollectionAdded(address indexed collection, uint256 tier);
    event StakingTierUpdated(uint256 tierId, uint256 rewardRate, uint256 boostMultiplier);

    constructor(address _ikigaiToken) {
        ikigaiToken = IkigaiTokenV2(_ikigaiToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize staking tiers
        stakingTiers.push(StakingTier({
            minStakeTime: 7 days,
            rewardRate: 100,      // 1% daily
            boostMultiplier: 150, // 1.5x boost
            maxBoost: 300        // 3x max boost
        }));
        
        stakingTiers.push(StakingTier({
            minStakeTime: 30 days,
            rewardRate: 150,      // 1.5% daily
            boostMultiplier: 200, // 2x boost
            maxBoost: 400        // 4x max boost
        }));
        
        stakingTiers.push(StakingTier({
            minStakeTime: 90 days,
            rewardRate: 200,      // 2% daily
            boostMultiplier: 300, // 3x boost
            maxBoost: 500        // 5x max boost
        }));
    }

    // Core staking functions
    function stakeNFT(
        address collection,
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        require(collections[collection].isSupported, "Collection not supported");
        require(
            userStakedTokens[msg.sender].length < MAX_STAKE_PER_USER,
            "Max stake limit reached"
        );
        
        IERC721 nft = IERC721(collection);
        require(
            nft.ownerOf(tokenId) == msg.sender,
            "Not token owner"
        );
        
        // Transfer NFT to contract
        nft.transferFrom(msg.sender, address(this), tokenId);
        
        // Create stake
        stakes[collection][tokenId] = NFTStake({
            tokenId: tokenId,
            startTime: block.timestamp,
            lastClaimTime: block.timestamp,
            accumulatedRewards: 0,
            isActive: true
        });
        
        userStakedTokens[msg.sender].push(tokenId);
        collections[collection].totalStaked++;
        
        emit NFTStaked(collection, tokenId, msg.sender);
    }

    function unstakeNFT(
        address collection,
        uint256 tokenId
    ) external nonReentrant {
        NFTStake storage stake = stakes[collection][tokenId];
        require(stake.isActive, "Not staked");
        require(
            block.timestamp >= stake.startTime + MIN_STAKE_DURATION,
            "Minimum stake period not met"
        );
        
        // Calculate and distribute final rewards
        uint256 rewards = calculateRewards(collection, tokenId);
        if (rewards > 0) {
            _distributeRewards(msg.sender, rewards);
            collections[collection].rewardsDistributed += rewards;
        }
        
        // Return NFT
        IERC721(collection).transferFrom(address(this), msg.sender, tokenId);
        
        // Update state
        stake.isActive = false;
        collections[collection].totalStaked--;
        _removeFromUserStakes(msg.sender, tokenId);
        
        emit NFTUnstaked(collection, tokenId, msg.sender);
    }

    function claimRewards(
        address collection,
        uint256 tokenId
    ) external nonReentrant whenNotPaused {
        NFTStake storage stake = stakes[collection][tokenId];
        require(stake.isActive, "Not staked");
        
        uint256 rewards = calculateRewards(collection, tokenId);
        require(rewards > 0, "No rewards to claim");
        
        stake.lastClaimTime = block.timestamp;
        stake.accumulatedRewards = 0;
        
        _distributeRewards(msg.sender, rewards);
        collections[collection].rewardsDistributed += rewards;
        
        emit RewardsClaimed(msg.sender, rewards);
    }

    // Reward calculation
    function calculateRewards(
        address collection,
        uint256 tokenId
    ) public view returns (uint256) {
        NFTStake storage stake = stakes[collection][tokenId];
        if (!stake.isActive) return 0;
        
        Collection storage col = collections[collection];
        StakingTier storage tier = stakingTiers[col.stakingTier];
        
        uint256 stakeDuration = block.timestamp - stake.lastClaimTime;
        if (stakeDuration < tier.minStakeTime) return 0;
        
        uint256 baseReward = (stakeDuration * tier.rewardRate) / 1 days;
        
        // Calculate boost
        uint256 totalStakeTime = block.timestamp - stake.startTime;
        uint256 boost = Math.min(
            (totalStakeTime * tier.boostMultiplier) / MAX_BOOST_DURATION,
            tier.maxBoost
        );
        
        return (baseReward * (10000 + boost)) / 10000;
    }

    // Internal functions
    function _distributeRewards(address user, uint256 amount) internal {
        require(
            ikigaiToken.transfer(user, amount),
            "Reward distribution failed"
        );
    }

    function _removeFromUserStakes(address user, uint256 tokenId) internal {
        uint256[] storage userTokens = userStakedTokens[user];
        for (uint256 i = 0; i < userTokens.length; i++) {
            if (userTokens[i] == tokenId) {
                userTokens[i] = userTokens[userTokens.length - 1];
                userTokens.pop();
                break;
            }
        }
    }

    // Admin functions
    function addCollection(
        address collection,
        uint256 tier
    ) external onlyRole(MANAGER_ROLE) {
        require(tier < stakingTiers.length, "Invalid tier");
        require(!collections[collection].isSupported, "Already supported");
        
        collections[collection] = Collection({
            isSupported: true,
            stakingTier: tier,
            totalStaked: 0,
            rewardsDistributed: 0,
            lastUpdateTime: block.timestamp
        });
        
        emit CollectionAdded(collection, tier);
    }

    function updateStakingTier(
        uint256 tierId,
        uint256 rewardRate,
        uint256 boostMultiplier,
        uint256 maxBoost
    ) external onlyRole(MANAGER_ROLE) {
        require(tierId < stakingTiers.length, "Invalid tier");
        require(rewardRate <= 500, "Rate too high"); // Max 5% daily
        require(maxBoost <= 1000, "Boost too high"); // Max 10x
        
        StakingTier storage tier = stakingTiers[tierId];
        tier.rewardRate = rewardRate;
        tier.boostMultiplier = boostMultiplier;
        tier.maxBoost = maxBoost;
        
        emit StakingTierUpdated(tierId, rewardRate, boostMultiplier);
    }

    // View functions
    function getUserStakes(
        address user
    ) external view returns (uint256[] memory) {
        return userStakedTokens[user];
    }

    function getStakeInfo(
        address collection,
        uint256 tokenId
    ) external view returns (NFTStake memory) {
        return stakes[collection][tokenId];
    }
} 