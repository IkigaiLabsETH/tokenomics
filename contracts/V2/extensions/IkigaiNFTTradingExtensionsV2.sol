// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiNFTTradingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TRADING_MANAGER = keccak256("TRADING_MANAGER");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    struct TradingStrategy {
        uint256 minProfit;         // Minimum profit target
        uint256 maxLoss;           // Maximum loss limit
        uint256 entryWindow;       // Time window for entry
        uint256 exitWindow;        // Time window for exit
        uint256 cooldownPeriod;    // Time between trades
        bool isActive;             // Whether strategy is active
    }

    struct TradePosition {
        uint256 tokenId;           // NFT token ID
        uint256 entryPrice;        // Entry price
        uint256 targetPrice;       // Target exit price
        uint256 stopLoss;          // Stop loss price
        uint256 timestamp;         // Position timestamp
        bool isLong;              // Long/short position
        bool isActive;            // Whether position is active
    }

    struct CollectionMetrics {
        uint256 floorPrice;        // Current floor price
        uint256 volume24h;         // 24h trading volume
        uint256 volatility;        // Price volatility
        uint256 liquidity;         // Market liquidity
        uint256 lastUpdate;        // Last update timestamp
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => TradingStrategy) public strategies;
    mapping(address => mapping(uint256 => TradePosition)) public positions;
    mapping(address => CollectionMetrics) public collectionMetrics;
    mapping(address => uint256) public tradingVolumes;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_PROFIT_TARGET = 500; // 5%
    uint256 public constant MAX_LOSS_LIMIT = 1000; // 10%
    
    // Events
    event StrategyCreated(bytes32 indexed strategyId, uint256 minProfit);
    event PositionOpened(address indexed collection, uint256 tokenId, uint256 price);
    event PositionClosed(address indexed collection, uint256 tokenId, uint256 profit);
    event MetricsUpdated(address indexed collection, uint256 floorPrice);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Strategy management
    function createTradingStrategy(
        bytes32 strategyId,
        uint256 minProfit,
        uint256 maxLoss,
        uint256 entryWindow,
        uint256 exitWindow,
        uint256 cooldownPeriod
    ) external onlyRole(TRADING_MANAGER) {
        require(!strategies[strategyId].isActive, "Strategy exists");
        require(minProfit >= MIN_PROFIT_TARGET, "Profit too low");
        require(maxLoss <= MAX_LOSS_LIMIT, "Loss too high");
        
        strategies[strategyId] = TradingStrategy({
            minProfit: minProfit,
            maxLoss: maxLoss,
            entryWindow: entryWindow,
            exitWindow: exitWindow,
            cooldownPeriod: cooldownPeriod,
            isActive: true
        });
        
        emit StrategyCreated(strategyId, minProfit);
    }

    // Position management
    function openPosition(
        bytes32 strategyId,
        address collection,
        uint256 tokenId,
        uint256 price,
        bool isLong
    ) external onlyRole(STRATEGY_ROLE) nonReentrant whenNotPaused {
        TradingStrategy storage strategy = strategies[strategyId];
        require(strategy.isActive, "Strategy not active");
        
        // Validate entry conditions
        require(
            _validateEntryConditions(collection, price),
            "Entry conditions not met"
        );
        
        // Create position
        positions[collection][tokenId] = TradePosition({
            tokenId: tokenId,
            entryPrice: price,
            targetPrice: isLong ? 
                price + (price * strategy.minProfit) / BASIS_POINTS :
                price - (price * strategy.minProfit) / BASIS_POINTS,
            stopLoss: isLong ?
                price - (price * strategy.maxLoss) / BASIS_POINTS :
                price + (price * strategy.maxLoss) / BASIS_POINTS,
            timestamp: block.timestamp,
            isLong: isLong,
            isActive: true
        });
        
        // Transfer NFT if long position
        if (isLong) {
            IERC721(collection).transferFrom(msg.sender, address(this), tokenId);
        }
        
        emit PositionOpened(collection, tokenId, price);
    }

    function closePosition(
        bytes32 strategyId,
        address collection,
        uint256 tokenId,
        uint256 price
    ) external onlyRole(STRATEGY_ROLE) nonReentrant {
        TradePosition storage position = positions[collection][tokenId];
        require(position.isActive, "Position not active");
        
        // Calculate profit/loss
        uint256 profitLoss = _calculateProfitLoss(position, price);
        
        // Update trading volume
        tradingVolumes[collection] += price;
        
        // Transfer NFT if long position
        if (position.isLong) {
            IERC721(collection).transferFrom(address(this), msg.sender, tokenId);
        }
        
        // Clear position
        position.isActive = false;
        
        emit PositionClosed(collection, tokenId, profitLoss);
    }

    // Market analysis
    function updateCollectionMetrics(
        address collection
    ) external onlyRole(TRADING_MANAGER) {
        CollectionMetrics storage metrics = collectionMetrics[collection];
        require(
            block.timestamp >= metrics.lastUpdate + 1 hours,
            "Too frequent"
        );
        
        // Get market data
        (uint256 floor, uint256 volume) = _getMarketData(collection);
        
        // Update metrics
        metrics.floorPrice = floor;
        metrics.volume24h = volume;
        metrics.volatility = _calculateVolatility(collection);
        metrics.liquidity = _calculateLiquidity(collection);
        metrics.lastUpdate = block.timestamp;
        
        emit MetricsUpdated(collection, floor);
    }

    // Internal functions
    function _validateEntryConditions(
        address collection,
        uint256 price
    ) internal view returns (bool) {
        CollectionMetrics storage metrics = collectionMetrics[collection];
        
        // Check price against floor
        if (price < metrics.floorPrice) {
            return false;
        }
        
        // Check liquidity
        if (metrics.liquidity < 1000) { // Minimum liquidity threshold
            return false;
        }
        
        // Check volatility
        if (metrics.volatility > 5000) { // Maximum volatility threshold (50%)
            return false;
        }
        
        return true;
    }

    function _calculateProfitLoss(
        TradePosition storage position,
        uint256 currentPrice
    ) internal view returns (uint256) {
        if (position.isLong) {
            return currentPrice > position.entryPrice ?
                (currentPrice - position.entryPrice) * BASIS_POINTS / position.entryPrice :
                0;
        } else {
            return position.entryPrice > currentPrice ?
                (position.entryPrice - currentPrice) * BASIS_POINTS / position.entryPrice :
                0;
        }
    }

    function _getMarketData(
        address collection
    ) internal view returns (uint256 floor, uint256 volume) {
        // Implementation needed - get data from marketplace/oracle
        return (0, 0);
    }

    function _calculateVolatility(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateLiquidity(
        address collection
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    // View functions
    function getStrategyInfo(
        bytes32 strategyId
    ) external view returns (TradingStrategy memory) {
        return strategies[strategyId];
    }

    function getPositionInfo(
        address collection,
        uint256 tokenId
    ) external view returns (TradePosition memory) {
        return positions[collection][tokenId];
    }

    function getCollectionMetrics(
        address collection
    ) external view returns (CollectionMetrics memory) {
        return collectionMetrics[collection];
    }

    function getTradingVolume(
        address collection
    ) external view returns (uint256) {
        return tradingVolumes[collection];
    }
} 