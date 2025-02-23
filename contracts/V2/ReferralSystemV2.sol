// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ReferralSystemV2 is ReentrancyGuard, AccessControl {
    struct Referrer {
        uint256 totalReferrals;
        uint256 activeReferrals;
        uint256 earnedRewards;
        uint256 lastRewardTimestamp;
    }

    mapping(address => Referrer) public referrers;
    mapping(address => address) public referredBy;
    mapping(address => bool) public isActive;

    uint256 public constant MAX_REFERRALS = 100;
    uint256 public constant MIN_ACTIVITY_PERIOD = 7 days;
    uint256 public constant REWARD_COOLDOWN = 1 days;
    
    // Declining rewards structure
    uint256[] public rewardTiers = [
        100, // 1.0% for first 20 referrals
        75,  // 0.75% for next 30
        50,  // 0.5% for next 50
        0    // 0% afterwards
    ];

    event ReferralRegistered(address indexed referrer, address indexed referred);
    event ReferralRewardPaid(address indexed referrer, uint256 amount);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function registerReferral(address referrer) 
        external 
        nonReentrant 
    {
        require(referrer != address(0), "Invalid referrer");
        require(referrer != msg.sender, "Cannot refer self");
        require(referredBy[msg.sender] == address(0), "Already referred");
        require(
            referrers[referrer].totalReferrals < MAX_REFERRALS,
            "Referrer at capacity"
        );

        referredBy[msg.sender] = referrer;
        referrers[referrer].totalReferrals++;
        
        emit ReferralRegistered(referrer, msg.sender);
    }

    function calculateRewardRate(address referrer) 
        public 
        view 
        returns (uint256) 
    {
        uint256 totalRefs = referrers[referrer].totalReferrals;
        
        if (totalRefs < 20) return rewardTiers[0];
        if (totalRefs < 50) return rewardTiers[1];
        if (totalRefs < 100) return rewardTiers[2];
        return rewardTiers[3];
    }

    // Additional functions would go here...
} 