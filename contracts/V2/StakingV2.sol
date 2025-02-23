// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract StakingV2 is ReentrancyGuard, AccessControl {
    struct Stake {
        uint256 amount;
        uint256 timestamp;
        uint256 lockPeriod;
        uint256 rewardMultiplier;
    }

    IERC20 public immutable ikigaiToken;
    
    // Lowered staking tiers
    uint256 public constant TIER1_THRESHOLD = 1_000 * 10**18; // 1,000 tokens
    uint256 public constant TIER2_THRESHOLD = 5_000 * 10**18; // 5,000 tokens
    uint256 public constant TIER3_THRESHOLD = 15_000 * 10**18; // 15,000 tokens

    // More gradual discount rates
    uint256 public constant TIER1_DISCOUNT = 5; // 5%
    uint256 public constant TIER2_DISCOUNT = 15; // 15%
    uint256 public constant TIER3_DISCOUNT = 25; // 25%

    mapping(address => Stake) public stakes;
    
    event Staked(address indexed user, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);

    constructor(address _ikigaiToken) {
        ikigaiToken = IERC20(_ikigaiToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function stake(uint256 amount, uint256 lockPeriod) 
        external 
        nonReentrant 
    {
        require(amount > 0, "Cannot stake 0");
        require(lockPeriod >= 7 days, "Min lock period is 7 days");
        require(lockPeriod <= 28 days, "Max lock period is 28 days");

        // Transfer tokens to contract
        require(
            ikigaiToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Calculate reward multiplier based on amount and lock period
        uint256 multiplier = calculateMultiplier(amount, lockPeriod);
        
        stakes[msg.sender] = Stake({
            amount: amount,
            timestamp: block.timestamp,
            lockPeriod: lockPeriod,
            rewardMultiplier: multiplier
        });

        emit Staked(msg.sender, amount, lockPeriod);
    }

    function calculateMultiplier(uint256 amount, uint256 lockPeriod) 
        public 
        pure 
        returns (uint256) 
    {
        uint256 baseMultiplier;
        
        if (amount >= TIER3_THRESHOLD) {
            baseMultiplier = TIER3_DISCOUNT;
        } else if (amount >= TIER2_THRESHOLD) {
            baseMultiplier = TIER2_DISCOUNT;
        } else if (amount >= TIER1_THRESHOLD) {
            baseMultiplier = TIER1_DISCOUNT;
        }

        // Additional multiplier based on lock period
        uint256 lockMultiplier = (lockPeriod * 5) / (7 days); // +5% per week
        
        return baseMultiplier + lockMultiplier;
    }

    // Additional functions would go here...
} 