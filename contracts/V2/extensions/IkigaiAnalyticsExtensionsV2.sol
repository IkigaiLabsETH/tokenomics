// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiAnalyticsExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant ANALYTICS_MANAGER = keccak256("ANALYTICS_MANAGER");
    bytes32 public constant REPORTER_ROLE = keccak256("REPORTER_ROLE");

    struct MarketMetrics {
        uint256 volume24h;       // 24h trading volume
        uint256 trades24h;       // 24h trade count
        uint256 uniqueTraders;   // Unique traders
        uint256 avgTradeSize;    // Average trade size
        uint256 lastUpdate;      // Last update time
    }

    struct TokenMetrics {
        uint256 price;           // Current price
        uint256 liquidity;       // Available liquidity
        uint256 marketCap;       // Market cap
        uint256 holders;         // Token holders
        uint256 lastTrade;       // Last trade time
    }

    struct TradingStats {
        uint256 totalVolume;     // Total volume
        uint256 totalTrades;     // Total trades
        uint256 successRate;     // Success rate
        uint256 profitLoss;      // P&L
        uint256 lastAction;      // Last action time
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => MarketMetrics) public marketMetrics;
    mapping(address => TokenMetrics) public tokenMetrics;
    mapping(address => TradingStats) public tradingStats;
    mapping(address => bool) public trackedTokens;
    
    uint256 public constant UPDATE_INTERVAL = 1 hours;
    uint256 public constant MAX_TRACKED_TOKENS = 1000;
    uint256 public constant MIN_LIQUIDITY = 1000e18;
    
    // Events
    event MetricsUpdated(bytes32 indexed marketId, uint256 timestamp);
    event TokenTracked(address indexed token, bool status);
    event StatsUpdated(address indexed trader, uint256 timestamp);
    event AlertTriggered(bytes32 indexed alertId, string details);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Market analysis
    function updateMarketMetrics(
        bytes32 marketId,
        uint256 volume,
        uint256 trades,
        uint256 traders
    ) external onlyRole(REPORTER_ROLE) {
        MarketMetrics storage metrics = marketMetrics[marketId];
        require(
            block.timestamp >= metrics.lastUpdate + UPDATE_INTERVAL,
            "Too frequent"
        );
        
        metrics.volume24h = volume;
        metrics.trades24h = trades;
        metrics.uniqueTraders = traders;
        metrics.avgTradeSize = trades > 0 ? volume / trades : 0;
        metrics.lastUpdate = block.timestamp;
        
        emit MetricsUpdated(marketId, block.timestamp);
    }

    // Token tracking
    function updateTokenMetrics(
        address token,
        uint256 price,
        uint256 liquidity,
        uint256 marketCap,
        uint256 holders
    ) external onlyRole(REPORTER_ROLE) {
        require(trackedTokens[token], "Token not tracked");
        require(liquidity >= MIN_LIQUIDITY, "Insufficient liquidity");
        
        TokenMetrics storage metrics = tokenMetrics[token];
        metrics.price = price;
        metrics.liquidity = liquidity;
        metrics.marketCap = marketCap;
        metrics.holders = holders;
        metrics.lastTrade = block.timestamp;
        
        // Check for significant changes
        _checkPriceDeviation(token, price);
        _checkLiquidityChange(token, liquidity);
        
        emit TokenTracked(token, true);
    }

    // Trading analysis
    function updateTradingStats(
        address trader,
        uint256 volume,
        uint256 trades,
        uint256 successRate,
        int256 pnl
    ) external onlyRole(REPORTER_ROLE) {
        TradingStats storage stats = tradingStats[trader];
        
        stats.totalVolume += volume;
        stats.totalTrades += trades;
        stats.successRate = ((stats.successRate * (stats.totalTrades - trades)) + (successRate * trades)) / stats.totalTrades;
        stats.profitLoss = uint256(int256(stats.profitLoss) + pnl);
        stats.lastAction = block.timestamp;
        
        // Check for anomalies
        _checkTradingAnomaly(trader, volume, successRate);
        
        emit StatsUpdated(trader, block.timestamp);
    }

    // Internal functions
    function _checkPriceDeviation(
        address token,
        uint256 newPrice
    ) internal {
        TokenMetrics storage metrics = tokenMetrics[token];
        uint256 deviation = _calculateDeviation(metrics.price, newPrice);
        
        if (deviation > 1000) { // 10% deviation
            emit AlertTriggered(
                keccak256(abi.encodePacked("PRICE_DEVIATION", token)),
                "Significant price movement detected"
            );
        }
    }

    function _checkLiquidityChange(
        address token,
        uint256 newLiquidity
    ) internal {
        TokenMetrics storage metrics = tokenMetrics[token];
        uint256 change = _calculateDeviation(metrics.liquidity, newLiquidity);
        
        if (change > 2000) { // 20% change
            emit AlertTriggered(
                keccak256(abi.encodePacked("LIQUIDITY_CHANGE", token)),
                "Significant liquidity change detected"
            );
        }
    }

    function _checkTradingAnomaly(
        address trader,
        uint256 volume,
        uint256 successRate
    ) internal {
        TradingStats storage stats = tradingStats[trader];
        
        if (volume > stats.totalVolume / 2) { // 50% of total volume
            emit AlertTriggered(
                keccak256(abi.encodePacked("VOLUME_ANOMALY", trader)),
                "Unusual trading volume detected"
            );
        }
        
        if (successRate < 2000) { // 20% success rate
            emit AlertTriggered(
                keccak256(abi.encodePacked("LOW_SUCCESS", trader)),
                "Low trading success rate detected"
            );
        }
    }

    function _calculateDeviation(
        uint256 oldValue,
        uint256 newValue
    ) internal pure returns (uint256) {
        if (oldValue == 0) return 0;
        
        uint256 diff = oldValue > newValue ? 
            oldValue - newValue : 
            newValue - oldValue;
            
        return (diff * 10000) / oldValue;
    }

    // View functions
    function getMarketMetrics(
        bytes32 marketId
    ) external view returns (MarketMetrics memory) {
        return marketMetrics[marketId];
    }

    function getTokenMetrics(
        address token
    ) external view returns (TokenMetrics memory) {
        return tokenMetrics[token];
    }

    function getTradingStats(
        address trader
    ) external view returns (TradingStats memory) {
        return tradingStats[trader];
    }

    function isTokenTracked(
        address token
    ) external view returns (bool) {
        return trackedTokens[token];
    }
} 