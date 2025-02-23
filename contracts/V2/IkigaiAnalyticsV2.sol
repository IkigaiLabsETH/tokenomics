// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract IkigaiAnalyticsV2 is AccessControl, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant AGGREGATOR_ROLE = keccak256("AGGREGATOR_ROLE");

    struct CollectionMetrics {
        uint256 floorPrice;
        uint256 volume24h;
        uint256 volumeTotal;
        uint256 holders;
        uint256 listings;
        uint256 avgHoldTime;
        uint256 lastSalePrice;
        uint256 lastUpdateTime;
    }

    struct UserMetrics {
        uint256 tradingVolume;
        uint256 stakingVolume;
        uint256 totalTrades;
        uint256 profitLoss;
        uint256 avgHoldTime;
        uint256 lastTradeTime;
        bool isActive;
    }

    struct MarketMetrics {
        uint256 totalVolume;
        uint256 activeUsers24h;
        uint256 newUsers24h;
        uint256 avgPrice24h;
        uint256 totalListings;
        uint256 totalSales;
    }

    // Storage
    mapping(address => CollectionMetrics) public collectionMetrics;
    mapping(address => UserMetrics) public userMetrics;
    MarketMetrics public marketMetrics;
    
    // Time-series data
    mapping(uint256 => mapping(address => CollectionMetrics)) public historicalMetrics;
    uint256 public constant SNAPSHOT_INTERVAL = 1 days;
    uint256 public lastSnapshotTime;

    // Events
    event MetricsUpdated(
        address indexed collection,
        uint256 floorPrice,
        uint256 volume24h,
        uint256 holders
    );
    
    event UserStatsUpdated(
        address indexed user,
        uint256 volume,
        uint256 trades,
        uint256 profitLoss
    );
    
    event MarketStatsUpdated(
        uint256 volume,
        uint256 activeUsers,
        uint256 avgPrice
    );

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Collection metrics functions
    function updateCollectionMetrics(
        address collection,
        uint256 floorPrice,
        uint256 volume24h,
        uint256 holders,
        uint256 listings,
        uint256 lastSalePrice
    ) external onlyRole(OPERATOR_ROLE) {
        CollectionMetrics storage metrics = collectionMetrics[collection];
        
        metrics.floorPrice = floorPrice;
        metrics.volume24h = volume24h;
        metrics.volumeTotal += volume24h;
        metrics.holders = holders;
        metrics.listings = listings;
        metrics.lastSalePrice = lastSalePrice;
        metrics.lastUpdateTime = block.timestamp;

        emit MetricsUpdated(collection, floorPrice, volume24h, holders);
        
        _checkAndCreateSnapshot();
    }

    // User metrics functions
    function updateUserMetrics(
        address user,
        uint256 tradeVolume,
        uint256 profitLoss,
        uint256 holdTime
    ) external onlyRole(OPERATOR_ROLE) {
        UserMetrics storage metrics = userMetrics[user];
        
        metrics.tradingVolume += tradeVolume;
        metrics.totalTrades++;
        metrics.profitLoss += profitLoss;
        metrics.avgHoldTime = ((metrics.avgHoldTime * (metrics.totalTrades - 1)) + holdTime) / metrics.totalTrades;
        metrics.lastTradeTime = block.timestamp;
        metrics.isActive = true;

        emit UserStatsUpdated(
            user,
            metrics.tradingVolume,
            metrics.totalTrades,
            metrics.profitLoss
        );
    }

    // Market-wide metrics
    function updateMarketMetrics(
        uint256 volume,
        uint256 activeUsers,
        uint256 newUsers,
        uint256 avgPrice
    ) external onlyRole(AGGREGATOR_ROLE) {
        marketMetrics.totalVolume += volume;
        marketMetrics.activeUsers24h = activeUsers;
        marketMetrics.newUsers24h = newUsers;
        marketMetrics.avgPrice24h = avgPrice;
        marketMetrics.totalListings = _calculateTotalListings();
        marketMetrics.totalSales++;

        emit MarketStatsUpdated(
            marketMetrics.totalVolume,
            activeUsers,
            avgPrice
        );
    }

    // Snapshot management
    function _checkAndCreateSnapshot() internal {
        if (block.timestamp >= lastSnapshotTime + SNAPSHOT_INTERVAL) {
            uint256 snapshotId = block.timestamp / SNAPSHOT_INTERVAL;
            _createSnapshot(snapshotId);
            lastSnapshotTime = block.timestamp;
        }
    }

    function _createSnapshot(uint256 snapshotId) internal {
        // Implement snapshot logic
    }

    // View functions
    function getCollectionStats(
        address collection
    ) external view returns (CollectionMetrics memory) {
        return collectionMetrics[collection];
    }

    function getUserStats(
        address user
    ) external view returns (UserMetrics memory) {
        return userMetrics[user];
    }

    function getMarketStats() external view returns (MarketMetrics memory) {
        return marketMetrics;
    }

    function getHistoricalMetrics(
        address collection,
        uint256 snapshotId
    ) external view returns (CollectionMetrics memory) {
        return historicalMetrics[snapshotId][collection];
    }

    // Internal helper functions
    function _calculateTotalListings() internal view returns (uint256) {
        // Implement listing calculation
        return 0;
    }
} 