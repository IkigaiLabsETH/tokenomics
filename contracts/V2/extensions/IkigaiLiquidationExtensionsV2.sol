// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiLiquidationExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant LIQUIDATION_MANAGER = keccak256("LIQUIDATION_MANAGER");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct LiquidationConfig {
        uint256 threshold;        // Liquidation threshold
        uint256 penalty;          // Liquidation penalty
        uint256 incentive;        // Keeper incentive
        uint256 gracePeriod;      // Grace period
        bool isActive;            // Config status
    }

    struct LiquidationEvent {
        address trader;           // Trader address
        uint256 amount;          // Liquidation amount
        uint256 penalty;         // Applied penalty
        uint256 timestamp;       // Event timestamp
        address keeper;          // Keeper address
    }

    struct HealthFactor {
        uint256 collateral;      // Collateral value
        uint256 debt;            // Debt value
        uint256 threshold;       // Current threshold
        uint256 ratio;           // Health ratio
        bool isHealthy;          // Health status
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => LiquidationConfig) public liquidationConfigs;
    mapping(bytes32 => mapping(address => LiquidationEvent[])) public liquidationEvents;
    mapping(address => HealthFactor) public healthFactors;
    mapping(address => bool) public whitelistedKeepers;
    
    uint256 public constant MAX_PENALTY = 1500; // 15%
    uint256 public constant MIN_HEALTH_RATIO = 11000; // 110%
    uint256 public constant GRACE_PERIOD = 1 hours;
    
    // Events
    event ConfigUpdated(bytes32 indexed configId, uint256 threshold);
    event PositionLiquidated(address indexed trader, uint256 amount);
    event KeeperRewarded(address indexed keeper, uint256 amount);
    event HealthUpdated(address indexed trader, uint256 ratio);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Configuration management
    function updateLiquidationConfig(
        bytes32 configId,
        LiquidationConfig calldata config
    ) external onlyRole(LIQUIDATION_MANAGER) {
        require(config.threshold >= MIN_HEALTH_RATIO, "Threshold too low");
        require(config.penalty <= MAX_PENALTY, "Penalty too high");
        require(config.gracePeriod <= GRACE_PERIOD, "Grace period too long");
        
        liquidationConfigs[configId] = config;
        
        emit ConfigUpdated(configId, config.threshold);
    }

    // Liquidation execution
    function liquidatePosition(
        bytes32 configId,
        address trader
    ) external onlyRole(KEEPER_ROLE) nonReentrant {
        require(whitelistedKeepers[msg.sender], "Not authorized");
        
        HealthFactor storage health = healthFactors[trader];
        require(!health.isHealthy, "Position healthy");
        
        LiquidationConfig storage config = liquidationConfigs[configId];
        require(config.isActive, "Config not active");
        
        // Calculate liquidation
        uint256 liquidationAmount = _calculateLiquidationAmount(trader);
        uint256 penalty = (liquidationAmount * config.penalty) / 10000;
        uint256 incentive = (liquidationAmount * config.incentive) / 10000;
        
        // Execute liquidation
        _executeLiquidation(
            trader,
            liquidationAmount,
            penalty,
            incentive,
            msg.sender
        );
        
        // Record event
        liquidationEvents[configId][trader].push(LiquidationEvent({
            trader: trader,
            amount: liquidationAmount,
            penalty: penalty,
            timestamp: block.timestamp,
            keeper: msg.sender
        }));
        
        emit PositionLiquidated(trader, liquidationAmount);
        emit KeeperRewarded(msg.sender, incentive);
    }

    // Health monitoring
    function updateHealthFactor(
        address trader
    ) external {
        uint256 collateral = _getCollateralValue(trader);
        uint256 debt = _getDebtValue(trader);
        
        uint256 ratio = (collateral * 10000) / debt;
        bool isHealthy = ratio >= MIN_HEALTH_RATIO;
        
        healthFactors[trader] = HealthFactor({
            collateral: collateral,
            debt: debt,
            threshold: MIN_HEALTH_RATIO,
            ratio: ratio,
            isHealthy: isHealthy
        });
        
        emit HealthUpdated(trader, ratio);
    }

    // Internal functions
    function _calculateLiquidationAmount(
        address trader
    ) internal view returns (uint256) {
        HealthFactor storage health = healthFactors[trader];
        return (health.debt * MIN_HEALTH_RATIO) / 10000;
    }

    function _executeLiquidation(
        address trader,
        uint256 amount,
        uint256 penalty,
        uint256 incentive,
        address keeper
    ) internal {
        // Implementation needed
    }

    function _getCollateralValue(
        address trader
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getDebtValue(
        address trader
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    // View functions
    function getLiquidationConfig(
        bytes32 configId
    ) external view returns (LiquidationConfig memory) {
        return liquidationConfigs[configId];
    }

    function getLiquidationEvents(
        bytes32 configId,
        address trader
    ) external view returns (LiquidationEvent[] memory) {
        return liquidationEvents[configId][trader];
    }

    function getHealthFactor(
        address trader
    ) external view returns (HealthFactor memory) {
        return healthFactors[trader];
    }

    function isKeeperWhitelisted(
        address keeper
    ) external view returns (bool) {
        return whitelistedKeepers[keeper];
    }
} 