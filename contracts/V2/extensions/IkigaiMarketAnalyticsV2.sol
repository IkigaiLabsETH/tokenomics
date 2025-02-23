// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiMarketAnalyticsV2 is AccessControl, ReentrancyGuard {
    bytes32 public constant ANALYTICS_MANAGER = keccak256("ANALYTICS_MANAGER");
    bytes32 public constant AGGREGATOR_ROLE = keccak256("AGGREGATOR_ROLE");

    struct CollectionMetrics {
        uint256 floorPrice;
        uint256 volume24h;
        uint256 volumeChange;     // Percent change
        uint256 averagePrice;
        uint256 highestSale;
        uint256 listingCount;
        uint256 holderCount;
        uint256 saleCount24h;
        uint256 uniqueBuyers24h;
        uint256 uniqueSellers24h;
        uint256 lastUpdateTime;
    }

    struct MarketTrend {
        uint256 timestamp;
        uint256 floorPrice;
        uint256 volume;
        uint256 listingCount;
        uint256 averagePrice;
        uint256 marketCap;
        bool isUptrend;
    }

    struct TradingActivity {
        uint256 buyCount;
        uint256 sellCount;
        uint256 totalVolume;
        uint256 averageHoldTime;
        uint256 profitLoss;
        uint256 lastTradeTime;
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(address => CollectionMetrics) public collectionMetrics;
    mapping(address => mapping(uint256 => MarketTrend)) public trends; // collection => timestamp => trend
    mapping(address => TradingActivity) public userActivity;
    mapping(address => uint256) public lastTrendUpdate;
    
    uint256 public constant TREND_INTERVAL = 1 hours;
    uint256 public constant METRICS_VALIDITY = 15 minutes;
    uint256 public constant MIN_DATA_POINTS = 24; // Minimum points for trend analysis
    
    // Events
    event MetricsUpdated(address indexed collection, uint256 floorPrice, uint256 volume24h);
    event TrendRecorded(address indexed collection, uint256 timestamp, bool isUptrend);
    event UserActivityUpdated(address indexed user, uint256 volume, int256 profitLoss);

    constructor(address _marketplace, address _oracle) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Core analytics functions
    function updateCollectionMetrics(
        address collection
    ) external onlyRole(AGGREGATOR_ROLE) {
        CollectionMetrics storage metrics = collectionMetrics[collection];
        require(
            block.timestamp >= metrics.lastUpdateTime + METRICS_VALIDITY,
            "Too soon to update"
        );
        
        // Get current marketplace data
        (uint256 floorPrice, uint256 volume24h) = getMarketplaceData(collection);
        
        // Calculate changes
        uint256 volumeChange = 0;
        if (metrics.volume24h > 0) {
            volumeChange = ((volume24h - metrics.volume24h) * 10000) / metrics.volume24h;
        }
        
        // Update metrics
        metrics.floorPrice = floorPrice;
        metrics.volume24h = volume24h;
        metrics.volumeChange = volumeChange;
        metrics.lastUpdateTime = block.timestamp;
        
        // Record trend if interval passed
        if (block.timestamp >= lastTrendUpdate[collection] + TREND_INTERVAL) {
            recordTrend(collection);
        }
        
        emit MetricsUpdated(collection, floorPrice, volume24h);
    }

    function recordTrend(address collection) internal {
        uint256 currentTimestamp = block.timestamp;
        MarketTrend storage trend = trends[collection][currentTimestamp];
        
        // Get current market state
        CollectionMetrics storage metrics = collectionMetrics[collection];
        
        // Calculate market cap (floor price * holder count)
        uint256 marketCap = metrics.floorPrice * metrics.holderCount;
        
        // Determine trend direction
        bool isUptrend = false;
        if (lastTrendUpdate[collection] > 0) {
            MarketTrend storage lastTrend = trends[collection][lastTrendUpdate[collection]];
            isUptrend = marketCap > lastTrend.marketCap;
        }
        
        // Record new trend
        trend.timestamp = currentTimestamp;
        trend.floorPrice = metrics.floorPrice;
        trend.volume = metrics.volume24h;
        trend.listingCount = metrics.listingCount;
        trend.averagePrice = metrics.averagePrice;
        trend.marketCap = marketCap;
        trend.isUptrend = isUptrend;
        
        lastTrendUpdate[collection] = currentTimestamp;
        
        emit TrendRecorded(collection, currentTimestamp, isUptrend);
    }

    function updateUserActivity(
        address user,
        bool isBuy,
        uint256 amount,
        int256 profitLoss
    ) external onlyRole(AGGREGATOR_ROLE) {
        TradingActivity storage activity = userActivity[user];
        
        if (isBuy) {
            activity.buyCount++;
        } else {
            activity.sellCount++;
        }
        
        activity.totalVolume += amount;
        activity.profitLoss += profitLoss;
        activity.lastTradeTime = block.timestamp;
        
        emit UserActivityUpdated(user, amount, profitLoss);
    }

    // Analysis functions
    function analyzeTrend(
        address collection,
        uint256 timeframe
    ) external view returns (
        bool isUptrend,
        uint256 priceChange,
        uint256 volumeChange,
        uint256 confidence
    ) {
        require(timeframe >= TREND_INTERVAL, "Timeframe too short");
        
        uint256 startTime = block.timestamp - timeframe;
        uint256 dataPoints = 0;
        uint256 uptrends = 0;
        
        MarketTrend storage firstTrend = trends[collection][startTime];
        MarketTrend storage lastTrend = trends[collection][lastTrendUpdate[collection]];
        
        // Calculate price and volume changes
        priceChange = ((lastTrend.floorPrice - firstTrend.floorPrice) * 10000) / firstTrend.floorPrice;
        volumeChange = ((lastTrend.volume - firstTrend.volume) * 10000) / firstTrend.volume;
        
        // Count uptrends
        for (uint256 t = startTime; t <= block.timestamp; t += TREND_INTERVAL) {
            if (trends[collection][t].timestamp > 0) {
                if (trends[collection][t].isUptrend) uptrends++;
                dataPoints++;
            }
        }
        
        require(dataPoints >= MIN_DATA_POINTS, "Insufficient data");
        
        isUptrend = uptrends > (dataPoints / 2);
        confidence = (uptrends * 10000) / dataPoints;
    }

    // View functions
    function getCollectionMetrics(
        address collection
    ) external view returns (CollectionMetrics memory) {
        return collectionMetrics[collection];
    }

    function getTrendHistory(
        address collection,
        uint256 startTime,
        uint256 endTime
    ) external view returns (MarketTrend[] memory) {
        uint256 count = (endTime - startTime) / TREND_INTERVAL + 1;
        MarketTrend[] memory history = new MarketTrend[](count);
        
        uint256 index = 0;
        for (uint256 t = startTime; t <= endTime; t += TREND_INTERVAL) {
            history[index] = trends[collection][t];
            index++;
        }
        
        return history;
    }

    function getUserStats(
        address user
    ) external view returns (TradingActivity memory) {
        return userActivity[user];
    }

    // Internal helpers
    function getMarketplaceData(
        address collection
    ) internal view returns (uint256 floorPrice, uint256 volume24h) {
        // Implementation needed - get data from marketplace contract
        return (0, 0);
    }
} 