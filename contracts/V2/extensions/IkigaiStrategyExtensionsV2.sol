// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiStrategyExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant STRATEGY_MANAGER = keccak256("STRATEGY_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct Strategy {
        string name;             // Strategy name
        uint256 targetPrice;     // Target price
        uint256 stopLoss;        // Stop loss price
        uint256 leverage;        // Leverage multiplier
        bool isActive;           // Strategy status
    }

    struct Position {
        uint256 entryPrice;      // Entry price
        uint256 size;            // Position size
        uint256 margin;          // Margin amount
        uint256 lastUpdate;      // Last update time
        bool isLong;             // Long/short flag
    }

    struct ExecutionParams {
        uint256 slippage;        // Max slippage
        uint256 deadline;        // Execution deadline
        uint256 minSize;         // Minimum size
        uint256 maxSize;         // Maximum size
        bool requiresApproval;   // Approval requirement
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => Strategy) public strategies;
    mapping(bytes32 => mapping(address => Position)) public positions;
    mapping(bytes32 => ExecutionParams) public executionParams;
    mapping(address => bool) public approvedTraders;
    
    uint256 public constant MAX_LEVERAGE = 10;
    uint256 public constant MAX_SLIPPAGE = 300; // 3%
    uint256 public constant MIN_MARGIN = 1000; // Min margin requirement
    
    // Events
    event StrategyCreated(bytes32 indexed strategyId, string name);
    event PositionOpened(bytes32 indexed strategyId, address indexed trader);
    event PositionClosed(bytes32 indexed strategyId, address indexed trader);
    event ExecutionUpdated(bytes32 indexed strategyId, uint256 slippage);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Strategy management
    function createStrategy(
        bytes32 strategyId,
        string calldata name,
        uint256 targetPrice,
        uint256 stopLoss,
        uint256 leverage
    ) external onlyRole(STRATEGY_MANAGER) {
        require(!strategies[strategyId].isActive, "Strategy exists");
        require(leverage <= MAX_LEVERAGE, "Leverage too high");
        require(stopLoss > 0, "Invalid stop loss");
        
        strategies[strategyId] = Strategy({
            name: name,
            targetPrice: targetPrice,
            stopLoss: stopLoss,
            leverage: leverage,
            isActive: true
        });
        
        emit StrategyCreated(strategyId, name);
    }

    // Position management
    function openPosition(
        bytes32 strategyId,
        uint256 size,
        bool isLong
    ) external nonReentrant whenNotPaused {
        require(approvedTraders[msg.sender], "Not approved");
        
        Strategy storage strategy = strategies[strategyId];
        require(strategy.isActive, "Strategy not active");
        
        ExecutionParams storage params = executionParams[strategyId];
        require(
            size >= params.minSize && size <= params.maxSize,
            "Invalid size"
        );
        
        // Calculate margin
        uint256 margin = _calculateRequiredMargin(size, strategy.leverage);
        require(margin >= MIN_MARGIN, "Margin too low");
        
        // Create position
        positions[strategyId][msg.sender] = Position({
            entryPrice: _getCurrentPrice(),
            size: size,
            margin: margin,
            lastUpdate: block.timestamp,
            isLong: isLong
        });
        
        emit PositionOpened(strategyId, msg.sender);
    }

    // Position monitoring
    function checkPositions(
        bytes32 strategyId,
        address trader
    ) external onlyRole(EXECUTOR_ROLE) {
        Position storage position = positions[strategyId][trader];
        Strategy storage strategy = strategies[strategyId];
        
        uint256 currentPrice = _getCurrentPrice();
        
        // Check stop loss
        if (position.isLong) {
            if (currentPrice <= strategy.stopLoss) {
                _closePosition(strategyId, trader);
            }
        } else {
            if (currentPrice >= strategy.stopLoss) {
                _closePosition(strategyId, trader);
            }
        }
        
        // Check target price
        if (position.isLong) {
            if (currentPrice >= strategy.targetPrice) {
                _closePosition(strategyId, trader);
            }
        } else {
            if (currentPrice <= strategy.targetPrice) {
                _closePosition(strategyId, trader);
            }
        }
    }

    // Internal functions
    function _calculateRequiredMargin(
        uint256 size,
        uint256 leverage
    ) internal pure returns (uint256) {
        return (size * 1000) / leverage;
    }

    function _getCurrentPrice() internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _closePosition(
        bytes32 strategyId,
        address trader
    ) internal {
        Position storage position = positions[strategyId][trader];
        
        // Calculate PnL
        uint256 currentPrice = _getCurrentPrice();
        uint256 pnl = _calculatePnL(position, currentPrice);
        
        // Update position
        delete positions[strategyId][trader];
        
        // Transfer funds
        // Implementation needed
        
        emit PositionClosed(strategyId, trader);
    }

    function _calculatePnL(
        Position memory position,
        uint256 currentPrice
    ) internal pure returns (uint256) {
        if (position.isLong) {
            return currentPrice > position.entryPrice ? 
                   (currentPrice - position.entryPrice) * position.size / 1e18 :
                   0;
        } else {
            return position.entryPrice > currentPrice ?
                   (position.entryPrice - currentPrice) * position.size / 1e18 :
                   0;
        }
    }

    // View functions
    function getStrategy(
        bytes32 strategyId
    ) external view returns (Strategy memory) {
        return strategies[strategyId];
    }

    function getPosition(
        bytes32 strategyId,
        address trader
    ) external view returns (Position memory) {
        return positions[strategyId][trader];
    }

    function getExecutionParams(
        bytes32 strategyId
    ) external view returns (ExecutionParams memory) {
        return executionParams[strategyId];
    }

    function isTraderApproved(
        address trader
    ) external view returns (bool) {
        return approvedTraders[trader];
    }
} 