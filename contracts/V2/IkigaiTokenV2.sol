// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract IkigaiTokenV2 is ERC20, ReentrancyGuard, AccessControl, Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18; // 1 billion tokens
    uint256 public constant DAILY_EMISSION_CAP = 684_931_506 * 10**18; // ~250M per year
    
    mapping(address => uint256) public lastMintTimestamp;
    mapping(address => uint256) public dailyMintedAmount;
    
    struct EmissionConfig {
        uint256 baseEmissionRate;    // Base daily emission rate
        uint256 minEmissionRate;     // Minimum daily emission
        uint256 maxEmissionRate;     // Maximum daily emission
        uint256 adjustmentInterval;  // Time between adjustments
        uint256 lastAdjustmentTime; // Last adjustment timestamp
    }

    struct MarketMetrics {
        uint256 tradingVolume;      // 24h trading volume
        uint256 stakingRatio;       // % of supply staked
        uint256 activeUsers;        // 24h active users
        uint256 averagePrice;       // 24h average price
    }

    EmissionConfig public emissionConfig;
    MarketMetrics public marketMetrics;
    
    event EmissionAdjusted(
        uint256 oldRate,
        uint256 newRate,
        string reason
    );
    
    event MarketMetricsUpdated(
        uint256 volume,
        uint256 stakingRatio,
        uint256 activeUsers,
        uint256 price
    );

    constructor() ERC20("Ikigai V2", "IKIGAI-V2") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        
        // Initialize emission config
        emissionConfig = EmissionConfig({
            baseEmissionRate: 684931 * 10**18,  // ~250M annually
            minEmissionRate: 342465 * 10**18,   // 50% of base
            maxEmissionRate: 1027396 * 10**18,  // 150% of base
            adjustmentInterval: 1 days,
            lastAdjustmentTime: block.timestamp
        });
    }

    function adjustEmissionRate() external whenNotPaused {
        require(
            block.timestamp >= emissionConfig.lastAdjustmentTime + emissionConfig.adjustmentInterval,
            "Too early for adjustment"
        );

        uint256 oldRate = emissionConfig.baseEmissionRate;
        uint256 newRate = oldRate;
        string memory reason;

        // Adjust based on trading volume
        if (marketMetrics.tradingVolume > 1000 ether) {
            newRate = Math.min(
                newRate + (newRate * 10) / 100,  // +10%
                emissionConfig.maxEmissionRate
            );
            reason = "High trading volume";
        }

        // Adjust based on staking ratio
        if (marketMetrics.stakingRatio < 2000) { // Less than 20% staked
            newRate = Math.max(
                newRate - (newRate * 5) / 100,   // -5%
                emissionConfig.minEmissionRate
            );
            reason = "Low staking ratio";
        }

        // Adjust based on active users
        if (marketMetrics.activeUsers > 1000) {
            newRate = Math.min(
                newRate + (newRate * 5) / 100,   // +5%
                emissionConfig.maxEmissionRate
            );
            reason = "High user activity";
        }

        emissionConfig.baseEmissionRate = newRate;
        emissionConfig.lastAdjustmentTime = block.timestamp;

        emit EmissionAdjusted(oldRate, newRate, reason);
    }

    function updateMarketMetrics(
        uint256 volume,
        uint256 stakingRatio,
        uint256 activeUsers,
        uint256 price
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        marketMetrics = MarketMetrics({
            tradingVolume: volume,
            stakingRatio: stakingRatio,
            activeUsers: activeUsers,
            averagePrice: price
        });

        emit MarketMetricsUpdated(volume, stakingRatio, activeUsers, price);
    }

    function mint(address to, uint256 amount) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
        nonReentrant 
    {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        
        // Reset daily minted amount if it's a new day
        if (block.timestamp >= lastMintTimestamp[to] + 1 days) {
            dailyMintedAmount[to] = 0;
        }
        
        uint256 currentEmissionRate = emissionConfig.baseEmissionRate;
        require(
            dailyMintedAmount[to] + amount <= currentEmissionRate,
            "Exceeds daily emission rate"
        );

        dailyMintedAmount[to] += amount;
        lastMintTimestamp[to] = block.timestamp;
        
        _mint(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
} 