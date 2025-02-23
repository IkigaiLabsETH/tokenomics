// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiNFT {
    // --- Structs ---
    struct StakingInfo {
        uint256 balance;
        uint256 rewardPerTokenPaid;
        uint256 rewards;
        uint256 lastClaimTime;
        uint256 stakeTimestamp;
    }

    struct PriorityConfig {
        uint256 discount;
        uint256 duration;
        uint256 startTime;
        uint256 maxPerNFT;
    }

    struct Series {
        uint256 id;
        uint256 price;
        uint256 maxSupply;
        uint256 currentSupply;
        uint256 startTime;
        bool isGenesis;
        bool active;
        uint256 requiredStake;
        uint256 stakeDuration;
    }

    // --- Events ---
    event NFTPurchased(address indexed buyer, uint256 tokenId, uint256 fee, uint256 sellerAmount);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event PriorityMint(address indexed buyer, uint256 beraNFTId, uint256 tokenId);
    event SeriesCreated(uint256 indexed seriesId, uint256 price, uint256 maxSupply, bool isGenesis);

    // --- Core Functions ---
    function priorityMint(uint256 beraNFTId) external;
    function buyNFT() external;
    function stake(uint256 amount) external;
    function withdrawStake(uint256 amount) external;
    function claimRewards() external;
    function mint(uint256 seriesId) external;

    // --- View Functions ---
    function earned(address account) external view returns (uint256);
    function getUserTier(address user) external view returns (uint256);
    function getStakingInfo(address account) external view returns (
        uint256 stakedBalance,
        uint256 earnedRewards,
        uint256 timeUntilUnlock,
        uint256 timeUntilNextClaim
    );
} 