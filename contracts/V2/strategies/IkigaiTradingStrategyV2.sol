// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";
import "../interfaces/IIkigaiMarketAnalyticsV2.sol";

contract IkigaiTradingStrategyV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant STRATEGY_MANAGER = keccak256("STRATEGY_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct StrategyConfig {
        uint256 maxPositionSize;    // Maximum size per position
        uint256 minProfitTarget;    // Minimum profit target (basis points)
        uint256 maxLossLimit;       // Maximum loss limit (basis points)
        uint256 minConfidence;      // Minimum trend confidence
        uint256 cooldownPeriod;     // Time between trades
        bool requiresAnalytics;     // Whether analytics are required
    }

    struct Position {
        uint256 tokenId;
        uint256 entryPrice;
        uint256 targetPrice;
        uint256 stopLoss;
        uint256 timestamp;
        bool isLong;               // True for buy, false for sell
        bool isActive;
    }

    struct TradeStats {
        uint256 totalTrades;
        uint256 successfulTrades;
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 bestTrade;
        uint256 worstTrade;
        uint256 averageHoldTime;
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    IIkigaiMarketAnalyticsV2 public analytics;
    
    mapping(address => mapping(uint256 => Position)) public positions; // collection => tokenId => position
    mapping(address => StrategyConfig) public strategyConfigs;
    mapping(address => TradeStats) public collectionStats;
    mapping(address => uint256) public lastTradeTime;
    
    uint256 public constant MAX_ACTIVE_POSITIONS = 50;
    uint256 public constant MIN_CONFIDENCE_THRESHOLD = 7000; // 70%
    uint256 public constant MAX_SLIPPAGE = 300; // 3%
    
    // Events
    event PositionOpened(
        address indexed collection,
        uint256 indexed tokenId,
        uint256 price,
        bool isLong
    );
    event PositionClosed(
        address indexed collection,
        uint256 indexed tokenId,
        uint256 price,
        int256 profitLoss
    );
    event StrategyConfigUpdated(
        address indexed collection,
        string parameter,
        uint256 value
    );

    constructor(
        address _marketplace,
        address _oracle,
        address _analytics
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        analytics = IIkigaiMarketAnalyticsV2(_analytics);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Core strategy functions
    function executeStrategy(
        address collection,
        uint256 tokenId
    ) external nonReentrant whenNotPaused onlyRole(EXECUTOR_ROLE) {
        StrategyConfig storage config = strategyConfigs[collection];
        require(config.maxPositionSize > 0, "Strategy not configured");
        
        // Check cooldown
        require(
            block.timestamp >= lastTradeTime[collection] + config.cooldownPeriod,
            "Cooldown active"
        );
        
        // Get market data
        (uint256 currentPrice, uint256 confidence) = getMarketData(collection);
        require(confidence >= config.minConfidence, "Low confidence");
        
        // Check if position exists
        Position storage position = positions[collection][tokenId];
        
        if (position.isActive) {
            _evaluateExitStrategy(collection, tokenId, currentPrice);
        } else {
            _evaluateEntryStrategy(collection, tokenId, currentPrice);
        }
        
        lastTradeTime[collection] = block.timestamp;
    }

    function _evaluateEntryStrategy(
        address collection,
        uint256 tokenId,
        uint256 currentPrice
    ) internal {
        // Get trend analysis
        (bool isUptrend, uint256 priceChange,,) = analytics.analyzeTrend(
            collection,
            24 hours
        );
        
        // Determine position type
        bool shouldEnterLong = isUptrend && priceChange >= strategyConfigs[collection].minProfitTarget;
        
        if (shouldEnterLong) {
            _openPosition(collection, tokenId, currentPrice, true);
        }
    }

    function _evaluateExitStrategy(
        address collection,
        uint256 tokenId,
        uint256 currentPrice
    ) internal {
        Position storage position = positions[collection][tokenId];
        
        // Calculate profit/loss
        int256 profitLoss;
        if (position.isLong) {
            profitLoss = int256(currentPrice) - int256(position.entryPrice);
        } else {
            profitLoss = int256(position.entryPrice) - int256(currentPrice);
        }
        
        // Check exit conditions
        bool shouldExit = false;
        
        // Target reached
        if (position.isLong && currentPrice >= position.targetPrice) {
            shouldExit = true;
        }
        // Stop loss hit
        if (position.isLong && currentPrice <= position.stopLoss) {
            shouldExit = true;
        }
        
        if (shouldExit) {
            _closePosition(collection, tokenId, currentPrice, profitLoss);
        }
    }

    function _openPosition(
        address collection,
        uint256 tokenId,
        uint256 entryPrice,
        bool isLong
    ) internal {
        StrategyConfig storage config = strategyConfigs[collection];
        
        // Calculate target and stop loss
        uint256 targetPrice = isLong ?
            entryPrice + ((entryPrice * config.minProfitTarget) / 10000) :
            entryPrice - ((entryPrice * config.minProfitTarget) / 10000);
            
        uint256 stopLoss = isLong ?
            entryPrice - ((entryPrice * config.maxLossLimit) / 10000) :
            entryPrice + ((entryPrice * config.maxLossLimit) / 10000);
        
        // Create position
        positions[collection][tokenId] = Position({
            tokenId: tokenId,
            entryPrice: entryPrice,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            timestamp: block.timestamp,
            isLong: isLong,
            isActive: true
        });
        
        emit PositionOpened(collection, tokenId, entryPrice, isLong);
    }

    function _closePosition(
        address collection,
        uint256 tokenId,
        uint256 exitPrice,
        int256 profitLoss
    ) internal {
        Position storage position = positions[collection][tokenId];
        TradeStats storage stats = collectionStats[collection];
        
        // Update stats
        stats.totalTrades++;
        if (profitLoss > 0) {
            stats.successfulTrades++;
            stats.totalProfit += uint256(profitLoss);
            if (uint256(profitLoss) > stats.bestTrade) {
                stats.bestTrade = uint256(profitLoss);
            }
        } else {
            stats.totalLoss += uint256(-profitLoss);
            if (uint256(-profitLoss) > stats.worstTrade) {
                stats.worstTrade = uint256(-profitLoss);
            }
        }
        
        uint256 holdTime = block.timestamp - position.timestamp;
        stats.averageHoldTime = (stats.averageHoldTime * (stats.totalTrades - 1) + holdTime) / stats.totalTrades;
        
        // Clear position
        delete positions[collection][tokenId];
        
        emit PositionClosed(collection, tokenId, exitPrice, profitLoss);
    }

    // Configuration
    function configureStrategy(
        address collection,
        uint256 maxPositionSize,
        uint256 minProfitTarget,
        uint256 maxLossLimit,
        uint256 minConfidence,
        uint256 cooldownPeriod,
        bool requiresAnalytics
    ) external onlyRole(STRATEGY_MANAGER) {
        require(maxLossLimit <= 5000, "Loss limit too high"); // Max 50%
        require(minConfidence >= MIN_CONFIDENCE_THRESHOLD, "Confidence too low");
        
        strategyConfigs[collection] = StrategyConfig({
            maxPositionSize: maxPositionSize,
            minProfitTarget: minProfitTarget,
            maxLossLimit: maxLossLimit,
            minConfidence: minConfidence,
            cooldownPeriod: cooldownPeriod,
            requiresAnalytics: requiresAnalytics
        });
        
        emit StrategyConfigUpdated(collection, "config", block.timestamp);
    }

    // View functions
    function getPositionInfo(
        address collection,
        uint256 tokenId
    ) external view returns (Position memory) {
        return positions[collection][tokenId];
    }

    function getTradeStats(
        address collection
    ) external view returns (TradeStats memory) {
        return collectionStats[collection];
    }

    // Internal helpers
    function getMarketData(
        address collection
    ) internal view returns (uint256 price, uint256 confidence) {
        // Implementation needed - get data from oracle
        return (0, 0);
    }
} 