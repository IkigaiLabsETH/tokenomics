// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./IkigaiTokenV2.sol";

/**
 * @title IkigaiMarketplaceExtensions
 * @dev Additional features that can be integrated with the existing marketplace
 * Focuses on advanced trading features, rewards, and ecosystem integration
 */
contract IkigaiMarketplaceExtensions is Initializable, OwnableUpgradeable, ReentrancyGuard, Pausable {
    // --- Advanced Trading Features ---
    struct ConditionalOrder {
        address maker;
        uint256 tokenId;
        uint256 price;
        uint256 expiry;
        OrderCondition condition;
        bool isActive;
    }

    struct OrderCondition {
        uint256 floorPrice;      // Floor price condition
        uint256 volumeThreshold; // Volume threshold
        uint256 timeWindow;      // Time window for conditions
        bool requiresStaking;    // Whether staking is required
        uint256 minStake;       // Minimum stake required
    }

    // --- Reward Tracking ---
    struct TradingStats {
        uint256 totalVolume;
        uint256 weeklyVolume;
        uint256 lastTradeTime;
        uint256 tradeCount;
        uint256 weeklyTradeCount;
        uint256 avgHoldTime;
    }

    // --- Ecosystem Integration ---
    struct CollectionMetrics {
        uint256 floorPrice;
        uint256 volume24h;
        uint256 holders;
        uint256 listings;
        uint256 lastUpdateTime;
    }

    // --- State Variables ---
    IkigaiTokenV2 public ikigaiToken;
    mapping(uint256 => ConditionalOrder[]) public conditionalOrders;
    mapping(address => TradingStats) public tradingStats;
    mapping(address => CollectionMetrics) public collectionMetrics;
    
    // Trading limits
    uint256 public constant MAX_ORDERS_PER_TOKEN = 5;
    uint256 public constant MIN_ORDER_DURATION = 1 hours;
    uint256 public constant MAX_ORDER_DURATION = 7 days;
    
    // Reward multipliers
    uint256 public constant WEEKLY_BONUS_THRESHOLD = 10; // 10 trades per week
    uint256 public constant HOLDING_BONUS_THRESHOLD = 30 days;
    
    // Events
    event ConditionalOrderCreated(
        address indexed maker,
        uint256 indexed tokenId,
        uint256 price,
        uint256 expiry
    );
    event OrderConditionMet(uint256 indexed tokenId, uint256 indexed orderId);
    event TradingStatsUpdated(address indexed trader, uint256 volume, uint256 count);
    event MetricsUpdated(address indexed collection, uint256 floorPrice, uint256 volume);

    function initialize(
        address _ikigaiToken
    ) public initializer {
        __Ownable_init();
        ikigaiToken = IkigaiTokenV2(_ikigaiToken);
    }

    // --- Advanced Trading Functions ---

    /**
     * @dev Create a conditional order with specific execution conditions
     */
    function createConditionalOrder(
        uint256 tokenId,
        uint256 price,
        uint256 duration,
        OrderCondition calldata condition
    ) external nonReentrant whenNotPaused {
        require(duration >= MIN_ORDER_DURATION, "Duration too short");
        require(duration <= MAX_ORDER_DURATION, "Duration too long");
        
        ConditionalOrder[] storage orders = conditionalOrders[tokenId];
        require(orders.length < MAX_ORDERS_PER_TOKEN, "Too many orders");

        // Validate conditions
        if (condition.requiresStaking) {
            require(
                ikigaiToken.balanceOf(msg.sender) >= condition.minStake,
                "Insufficient stake"
            );
        }

        orders.push(ConditionalOrder({
            maker: msg.sender,
            tokenId: tokenId,
            price: price,
            expiry: block.timestamp + duration,
            condition: condition,
            isActive: true
        }));

        emit ConditionalOrderCreated(msg.sender, tokenId, price, block.timestamp + duration);
    }

    /**
     * @dev Check and execute conditional orders if conditions are met
     */
    function checkAndExecuteOrders(
        uint256 tokenId,
        uint256 floorPrice,
        uint256 volume
    ) external nonReentrant {
        ConditionalOrder[] storage orders = conditionalOrders[tokenId];
        
        for (uint256 i = 0; i < orders.length; i++) {
            ConditionalOrder storage order = orders[i];
            if (!order.isActive || block.timestamp > order.expiry) continue;

            if (_checkConditions(order, floorPrice, volume)) {
                order.isActive = false;
                emit OrderConditionMet(tokenId, i);
                // Integration point with main marketplace for execution
            }
        }
    }

    // --- Trading Analytics ---

    /**
     * @dev Update trading statistics for a user
     */
    function updateTradingStats(
        address trader,
        uint256 volume
    ) external onlyOwner {
        TradingStats storage stats = tradingStats[trader];
        
        // Update weekly stats
        if (block.timestamp >= stats.lastTradeTime + 1 weeks) {
            stats.weeklyVolume = volume;
            stats.weeklyTradeCount = 1;
        } else {
            stats.weeklyVolume += volume;
            stats.weeklyTradeCount++;
        }
        
        // Update total stats
        stats.totalVolume += volume;
        stats.tradeCount++;
        stats.lastTradeTime = block.timestamp;
        
        emit TradingStatsUpdated(trader, volume, stats.tradeCount);
    }

    /**
     * @dev Calculate trading rewards based on activity
     */
    function calculateTradingRewards(
        address trader
    ) public view returns (uint256) {
        TradingStats storage stats = tradingStats[trader];
        uint256 baseReward = stats.weeklyVolume / 100; // 1% base reward
        
        // Weekly activity bonus
        if (stats.weeklyTradeCount >= WEEKLY_BONUS_THRESHOLD) {
            baseReward += baseReward / 5; // 20% bonus
        }
        
        // Holding time bonus
        if (stats.avgHoldTime >= HOLDING_BONUS_THRESHOLD) {
            baseReward += baseReward / 10; // 10% bonus
        }
        
        return baseReward;
    }

    // --- Collection Metrics ---

    /**
     * @dev Update collection metrics
     */
    function updateCollectionMetrics(
        address collection,
        uint256 floorPrice,
        uint256 volume,
        uint256 holders,
        uint256 listings
    ) external onlyOwner {
        CollectionMetrics storage metrics = collectionMetrics[collection];
        
        metrics.floorPrice = floorPrice;
        metrics.volume24h = volume;
        metrics.holders = holders;
        metrics.listings = listings;
        metrics.lastUpdateTime = block.timestamp;
        
        emit MetricsUpdated(collection, floorPrice, volume);
    }

    // --- Internal Functions ---

    function _checkConditions(
        ConditionalOrder storage order,
        uint256 floorPrice,
        uint256 volume
    ) internal view returns (bool) {
        OrderCondition storage condition = order.condition;
        
        bool floorCondition = floorPrice >= condition.floorPrice;
        bool volumeCondition = volume >= condition.volumeThreshold;
        
        if (condition.requiresStaking) {
            bool stakingCondition = ikigaiToken.balanceOf(order.maker) >= condition.minStake;
            return floorCondition && volumeCondition && stakingCondition;
        }
        
        return floorCondition && volumeCondition;
    }

    // --- View Functions ---

    function getTraderStats(
        address trader
    ) external view returns (
        uint256 totalVolume,
        uint256 weeklyVolume,
        uint256 tradeCount,
        uint256 weeklyTradeCount
    ) {
        TradingStats storage stats = tradingStats[trader];
        return (
            stats.totalVolume,
            stats.weeklyVolume,
            stats.tradeCount,
            stats.weeklyTradeCount
        );
    }

    function getCollectionMetrics(
        address collection
    ) external view returns (CollectionMetrics memory) {
        return collectionMetrics[collection];
    }
} 