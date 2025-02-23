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
        uint256 totalVolume;      // Total trading volume
        uint256 uniqueTraders;    // Unique traders
        uint256 avgPrice;         // Average price
        uint256 floorPrice;       // Floor price
        uint256 lastUpdate;       // Last update time
    }

    struct CollectionMetrics {
        uint256 totalSales;       // Total sales
        uint256 uniqueHolders;    // Unique holders
        uint256 avgHoldTime;      // Average hold time
        uint256 tradeVelocity;    // Trade velocity
        uint256 lastTrade;        // Last trade time
    }

    struct UserMetrics {
        uint256 totalTrades;      // Total trades
        uint256 totalVolume;      // Trading volume
        uint256 profitLoss;       // Profit/loss
        uint256 avgHoldTime;      // Average hold time
        uint256 lastActivity;     // Last activity time
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => MarketMetrics) public marketMetrics;
    mapping(address => CollectionMetrics) public collectionMetrics;
    mapping(address => UserMetrics) public userMetrics;
    mapping(address => bool) public trackedCollections;
    
    uint256 public constant UPDATE_INTERVAL = 1 hours;
    uint256 public constant MAX_TRACKED_COLLECTIONS = 1000;
    uint256 public constant METRICS_TTL = 7 days;
    
    // Events
    event MetricsUpdated(bytes32 indexed marketId, uint256 timestamp);
    event CollectionTracked(address indexed collection, uint256 timestamp);
    event UserActivityRecorded(address indexed user, uint256 volume);
    event MarketSnapshot(bytes32 indexed marketId, uint256 volume);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Market tracking
    function updateMarketMetrics(
        bytes32 marketId,
        uint256 volume,
        uint256 price
    ) external onlyRole(REPORTER_ROLE) {
        MarketMetrics storage metrics = marketMetrics[marketId];
        require(
            block.timestamp >= metrics.lastUpdate + UPDATE_INTERVAL,
            "Too frequent"
        );
        
        // Update metrics
        metrics.totalVolume += volume;
        metrics.avgPrice = _calculateMovingAverage(metrics.avgPrice, price);
        metrics.floorPrice = _getFloorPrice(marketId);
        metrics.lastUpdate = block.timestamp;
        
        emit MetricsUpdated(marketId, block.timestamp);
    }

    // Collection tracking
    function trackCollection(
        address collection
    ) external onlyRole(ANALYTICS_MANAGER) {
        require(!trackedCollections[collection], "Already tracked");
        require(
            _getTrackedCollectionCount() < MAX_TRACKED_COLLECTIONS,
            "Too many collections"
        );
        
        trackedCollections[collection] = true;
        
        // Initialize metrics
        collectionMetrics[collection] = CollectionMetrics({
            totalSales: 0,
            uniqueHolders: _getUniqueHolders(collection),
            avgHoldTime: 0,
            tradeVelocity: 0,
            lastTrade: block.timestamp
        });
        
        emit CollectionTracked(collection, block.timestamp);
    }

    // User activity tracking
    function recordUserActivity(
        address user,
        uint256 volume,
        bool isBuy
    ) external onlyRole(REPORTER_ROLE) {
        UserMetrics storage metrics = userMetrics[user];
        
        // Update metrics
        metrics.totalTrades++;
        metrics.totalVolume += volume;
        metrics.lastActivity = block.timestamp;
        
        if (isBuy) {
            metrics.profitLoss -= volume;
        } else {
            metrics.profitLoss += volume;
        }
        
        emit UserActivityRecorded(user, volume);
    }

    // Internal functions
    function _calculateMovingAverage(
        uint256 currentAvg,
        uint256 newValue
    ) internal pure returns (uint256) {
        return (currentAvg * 9 + newValue) / 10;
    }

    function _getFloorPrice(
        bytes32 marketId
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getUniqueHolders(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getTrackedCollectionCount() internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    // View functions
    function getMarketMetrics(
        bytes32 marketId
    ) external view returns (MarketMetrics memory) {
        return marketMetrics[marketId];
    }

    function getCollectionMetrics(
        address collection
    ) external view returns (CollectionMetrics memory) {
        return collectionMetrics[collection];
    }

    function getUserMetrics(
        address user
    ) external view returns (UserMetrics memory) {
        return userMetrics[user];
    }

    function isCollectionTracked(
        address collection
    ) external view returns (bool) {
        return trackedCollections[collection];
    }
} 