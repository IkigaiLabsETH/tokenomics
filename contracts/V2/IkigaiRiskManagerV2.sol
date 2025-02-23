// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IIkigaiOracleV2.sol";
import "./interfaces/IIkigaiVaultV2.sol";
import "./interfaces/IIkigaiMarketplaceV2.sol";

contract IkigaiRiskManagerV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant RISK_MANAGER = keccak256("RISK_MANAGER");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    struct RiskConfig {
        uint256 maxExposure;        // Maximum exposure per collection
        uint256 volatilityLimit;    // Maximum allowed volatility
        uint256 liquidityThreshold; // Minimum liquidity required
        uint256 concentrationLimit; // Maximum holder concentration
        uint256 timeWindow;         // Time window for checks
        bool requiresAudit;         // Whether collection audit is required
    }

    struct RiskMetrics {
        uint256 currentExposure;
        uint256 volatility24h;
        uint256 liquidityDepth;
        uint256 topHolderShare;
        uint256 activePositions;
        uint256 lastCheck;
        bool isHighRisk;
    }

    struct CircuitBreaker {
        uint256 priceThreshold;    // Price change threshold
        uint256 volumeThreshold;   // Volume spike threshold
        uint256 timeThreshold;     // Time window for checks
        uint256 consecutiveTriggers; // Required consecutive triggers
        bool isActive;
    }

    // State variables
    IIkigaiOracleV2 public oracle;
    IIkigaiVaultV2 public vault;
    IIkigaiMarketplaceV2 public marketplace;
    
    mapping(address => RiskConfig) public riskConfigs;
    mapping(address => RiskMetrics) public riskMetrics;
    mapping(address => CircuitBreaker) public circuitBreakers;
    mapping(address => uint256) public riskScores;
    
    uint256 public constant MAX_RISK_SCORE = 100;
    uint256 public constant CRITICAL_RISK_THRESHOLD = 80;
    uint256 public constant RISK_CHECK_INTERVAL = 1 hours;
    
    // Events
    event RiskConfigUpdated(address indexed collection, string parameter, uint256 value);
    event RiskLevelChanged(address indexed collection, uint256 oldScore, uint256 newScore);
    event CircuitBreakerTriggered(address indexed collection, string reason);
    event EmergencyShutdown(address indexed initiator, string reason);

    constructor(
        address _oracle,
        address _vault,
        address _marketplace
    ) {
        oracle = IIkigaiOracleV2(_oracle);
        vault = IIkigaiVaultV2(_vault);
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Core risk management functions
    function checkRiskLevel(
        address collection
    ) external nonReentrant returns (uint256 riskScore) {
        RiskMetrics storage metrics = riskMetrics[collection];
        require(
            block.timestamp >= metrics.lastCheck + RISK_CHECK_INTERVAL,
            "Too frequent"
        );
        
        // Get current metrics
        (
            uint256 exposure,
            uint256 volatility,
            uint256 liquidity,
            uint256 concentration
        ) = getCurrentMetrics(collection);
        
        // Update stored metrics
        metrics.currentExposure = exposure;
        metrics.volatility24h = volatility;
        metrics.liquidityDepth = liquidity;
        metrics.topHolderShare = concentration;
        metrics.lastCheck = block.timestamp;
        
        // Calculate risk score
        uint256 oldScore = riskScores[collection];
        riskScore = calculateRiskScore(collection, metrics);
        riskScores[collection] = riskScore;
        
        // Check if risk level changed significantly
        if (Math.abs(int256(riskScore) - int256(oldScore)) >= 10) {
            emit RiskLevelChanged(collection, oldScore, riskScore);
        }
        
        // Check circuit breakers
        if (riskScore >= CRITICAL_RISK_THRESHOLD) {
            _evaluateCircuitBreakers(collection);
        }
        
        return riskScore;
    }

    function _evaluateCircuitBreakers(address collection) internal {
        CircuitBreaker storage breaker = circuitBreakers[collection];
        if (!breaker.isActive) return;
        
        bool shouldTrigger = false;
        string memory reason = "";
        
        // Check price change
        uint256 priceChange = getPriceChange(collection);
        if (priceChange >= breaker.priceThreshold) {
            shouldTrigger = true;
            reason = "Price threshold exceeded";
        }
        
        // Check volume spike
        uint256 volumeSpike = getVolumeSpike(collection);
        if (volumeSpike >= breaker.volumeThreshold) {
            shouldTrigger = true;
            reason = "Volume threshold exceeded";
        }
        
        if (shouldTrigger) {
            breaker.consecutiveTriggers++;
            if (breaker.consecutiveTriggers >= 3) {
                triggerCircuitBreaker(collection, reason);
            }
        } else {
            breaker.consecutiveTriggers = 0;
        }
    }

    function triggerCircuitBreaker(
        address collection,
        string memory reason
    ) internal {
        // Pause trading for collection
        marketplace.pauseCollection(collection);
        
        // Close active positions
        vault.closePositions(collection);
        
        emit CircuitBreakerTriggered(collection, reason);
    }

    // Risk configuration
    function configureRiskParams(
        address collection,
        uint256 maxExposure,
        uint256 volatilityLimit,
        uint256 liquidityThreshold,
        uint256 concentrationLimit,
        uint256 timeWindow,
        bool requiresAudit
    ) external onlyRole(RISK_MANAGER) {
        riskConfigs[collection] = RiskConfig({
            maxExposure: maxExposure,
            volatilityLimit: volatilityLimit,
            liquidityThreshold: liquidityThreshold,
            concentrationLimit: concentrationLimit,
            timeWindow: timeWindow,
            requiresAudit: requiresAudit
        });
        
        emit RiskConfigUpdated(collection, "config", block.timestamp);
    }

    function configureCircuitBreaker(
        address collection,
        uint256 priceThreshold,
        uint256 volumeThreshold,
        uint256 timeThreshold
    ) external onlyRole(RISK_MANAGER) {
        circuitBreakers[collection] = CircuitBreaker({
            priceThreshold: priceThreshold,
            volumeThreshold: volumeThreshold,
            timeThreshold: timeThreshold,
            consecutiveTriggers: 0,
            isActive: true
        });
    }

    // Emergency functions
    function emergencyShutdown(
        string memory reason
    ) external onlyRole(GUARDIAN_ROLE) {
        _pause();
        vault.pause();
        marketplace.pause();
        
        emit EmergencyShutdown(msg.sender, reason);
    }

    // View functions
    function getRiskMetrics(
        address collection
    ) external view returns (RiskMetrics memory) {
        return riskMetrics[collection];
    }

    function getCircuitBreakerStatus(
        address collection
    ) external view returns (CircuitBreaker memory) {
        return circuitBreakers[collection];
    }

    // Internal helpers
    function getCurrentMetrics(
        address collection
    ) internal view returns (
        uint256 exposure,
        uint256 volatility,
        uint256 liquidity,
        uint256 concentration
    ) {
        // Implementation needed - get metrics from various sources
        return (0, 0, 0, 0);
    }

    function calculateRiskScore(
        address collection,
        RiskMetrics memory metrics
    ) internal view returns (uint256) {
        // Implementation needed - calculate risk score based on metrics
        return 0;
    }

    function getPriceChange(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed - get price change from oracle
        return 0;
    }

    function getVolumeSpike(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed - get volume spike from marketplace
        return 0;
    }
} 