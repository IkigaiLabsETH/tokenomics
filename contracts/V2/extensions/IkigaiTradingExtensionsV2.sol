// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiTradingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TRADING_MANAGER = keccak256("TRADING_MANAGER");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    struct TradingConfig {
        uint256 maxPosition;       // Maximum position size
        uint256 minPosition;       // Minimum position size
        uint256 maxSlippage;       // Maximum slippage
        uint256 cooldownPeriod;    // Trade cooldown period
        bool requiresApproval;     // Whether approval required
    }

    struct TradeStats {
        uint256 totalTrades;       // Total number of trades
        uint256 successfulTrades;  // Successful trades
        uint256 failedTrades;      // Failed trades
        uint256 totalVolume;       // Total trading volume
        uint256 lastTrade;         // Last trade timestamp
    }

    struct Position {
        uint256 entryPrice;        // Entry price
        uint256 quantity;          // Position quantity
        uint256 leverage;          // Position leverage
        uint256 liquidationPrice;  // Liquidation price
        bool isLong;               // Long/short position
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => TradingConfig) public tradingConfigs;
    mapping(bytes32 => TradeStats) public tradeStats;
    mapping(bytes32 => mapping(address => Position)) public positions;
    mapping(address => bool) public approvedTraders;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_LEVERAGE = 10;
    uint256 public constant MIN_COOLDOWN = 1 minutes;
    
    // Events
    event StrategyConfigured(bytes32 indexed strategyId, uint256 maxPosition);
    event TradeExecuted(bytes32 indexed strategyId, uint256 amount, bool isLong);
    event PositionUpdated(bytes32 indexed strategyId, address indexed trader);
    event TradeAlert(bytes32 indexed strategyId, string message);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Strategy configuration
    function configureStrategy(
        bytes32 strategyId,
        TradingConfig calldata config
    ) external onlyRole(TRADING_MANAGER) {
        require(config.maxPosition > config.minPosition, "Invalid position limits");
        require(config.maxSlippage <= 1000, "Slippage too high"); // Max 10%
        
        tradingConfigs[strategyId] = config;
        
        emit StrategyConfigured(strategyId, config.maxPosition);
    }

    // Trade execution
    function executeTrade(
        bytes32 strategyId,
        uint256 amount,
        bool isLong,
        uint256 leverage
    ) external onlyRole(STRATEGY_ROLE) nonReentrant {
        require(approvedTraders[msg.sender], "Not approved");
        require(leverage <= MAX_LEVERAGE, "Leverage too high");
        
        TradingConfig storage config = tradingConfigs[strategyId];
        TradeStats storage stats = tradeStats[strategyId];
        
        // Validate trade
        require(
            amount >= config.minPosition && amount <= config.maxPosition,
            "Invalid position size"
        );
        
        // Check cooldown
        require(
            block.timestamp >= stats.lastTrade + config.cooldownPeriod,
            "Cooldown active"
        );
        
        // Execute trade
        bool success = _executeTrade(strategyId, amount, isLong, leverage);
        
        // Update stats
        stats.totalTrades++;
        if (success) {
            stats.successfulTrades++;
        } else {
            stats.failedTrades++;
        }
        stats.totalVolume += amount;
        stats.lastTrade = block.timestamp;
        
        emit TradeExecuted(strategyId, amount, isLong);
    }

    // Position management
    function updatePosition(
        bytes32 strategyId,
        address trader,
        uint256 price,
        uint256 quantity
    ) external onlyRole(STRATEGY_ROLE) {
        Position storage position = positions[strategyId][trader];
        
        // Update position
        position.entryPrice = price;
        position.quantity = quantity;
        position.liquidationPrice = _calculateLiquidationPrice(
            price,
            position.leverage,
            position.isLong
        );
        
        emit PositionUpdated(strategyId, trader);
    }

    // Risk management
    function checkPositionHealth(
        bytes32 strategyId,
        address trader
    ) external view returns (bool isHealthy, string memory reason) {
        Position storage position = positions[strategyId][trader];
        
        // Get current price
        uint256 currentPrice = oracle.getAggregatedPrice(address(0))[0];
        
        // Check liquidation
        if (position.isLong) {
            if (currentPrice <= position.liquidationPrice) {
                return (false, "Long position liquidated");
            }
        } else {
            if (currentPrice >= position.liquidationPrice) {
                return (false, "Short position liquidated");
            }
        }
        
        return (true, "Position healthy");
    }

    // Internal functions
    function _executeTrade(
        bytes32 strategyId,
        uint256 amount,
        bool isLong,
        uint256 leverage
    ) internal returns (bool) {
        // Implementation needed
        return false;
    }

    function _calculateLiquidationPrice(
        uint256 entryPrice,
        uint256 leverage,
        bool isLong
    ) internal pure returns (uint256) {
        if (isLong) {
            return entryPrice * (100 - leverage) / 100;
        } else {
            return entryPrice * (100 + leverage) / 100;
        }
    }

    function _validateTrade(
        bytes32 strategyId,
        uint256 amount,
        uint256 price
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    // View functions
    function getTradingConfig(
        bytes32 strategyId
    ) external view returns (TradingConfig memory) {
        return tradingConfigs[strategyId];
    }

    function getTradeStats(
        bytes32 strategyId
    ) external view returns (TradeStats memory) {
        return tradeStats[strategyId];
    }

    function getPosition(
        bytes32 strategyId,
        address trader
    ) external view returns (Position memory) {
        return positions[strategyId][trader];
    }

    function isTraderApproved(
        address trader
    ) external view returns (bool) {
        return approvedTraders[trader];
    }
} 