// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiTradingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TRADING_MANAGER = keccak256("TRADING_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct Order {
        bytes32 id;              // Order ID
        address trader;          // Trader address
        address tokenIn;         // Input token
        address tokenOut;        // Output token
        uint256 amountIn;       // Input amount
        uint256 amountOut;      // Output amount
        uint256 price;          // Execution price
        uint256 deadline;       // Expiration time
        OrderStatus status;      // Order status
    }

    struct TradingConfig {
        uint256 minOrderSize;    // Minimum order size
        uint256 maxOrderSize;    // Maximum order size
        uint256 maxSlippage;     // Maximum slippage
        uint256 tradingFee;      // Trading fee
        bool requiresApproval;   // Approval requirement
    }

    struct TradingStats {
        uint256 totalVolume;     // Total volume
        uint256 totalTrades;     // Total trades
        uint256 avgPrice;        // Average price
        uint256 lastTrade;       // Last trade time
        uint256 fees;            // Collected fees
    }

    enum OrderStatus {
        PENDING,
        EXECUTED,
        CANCELLED,
        EXPIRED
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => Order) public orders;
    mapping(bytes32 => TradingConfig) public tradingConfigs;
    mapping(address => TradingStats) public tradingStats;
    mapping(address => bool) public approvedTraders;
    
    uint256 public constant MAX_FEE = 300; // 3%
    uint256 public constant MAX_SLIPPAGE = 1000; // 10%
    uint256 public constant MIN_ORDER_TTL = 1 minutes;
    
    // Events
    event OrderCreated(bytes32 indexed orderId, address indexed trader);
    event OrderExecuted(bytes32 indexed orderId, uint256 price);
    event OrderCancelled(bytes32 indexed orderId, string reason);
    event TradeSettled(bytes32 indexed orderId, uint256 fee);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Order management
    function createOrder(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (bytes32) {
        require(approvedTraders[msg.sender], "Not approved");
        require(deadline > block.timestamp + MIN_ORDER_TTL, "Invalid deadline");
        
        bytes32 orderId = keccak256(
            abi.encode(
                msg.sender,
                tokenIn,
                tokenOut,
                amountIn,
                block.timestamp
            )
        );
        
        TradingConfig storage config = tradingConfigs[orderId];
        require(
            amountIn >= config.minOrderSize &&
            amountIn <= config.maxOrderSize,
            "Invalid size"
        );
        
        // Create order
        orders[orderId] = Order({
            id: orderId,
            trader: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            amountOut: amountOut,
            price: _getCurrentPrice(tokenIn, tokenOut),
            deadline: deadline,
            status: OrderStatus.PENDING
        });
        
        // Transfer tokens
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        
        emit OrderCreated(orderId, msg.sender);
        return orderId;
    }

    // Order execution
    function executeOrder(
        bytes32 orderId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.PENDING, "Invalid status");
        require(block.timestamp <= order.deadline, "Order expired");
        
        uint256 currentPrice = _getCurrentPrice(order.tokenIn, order.tokenOut);
        require(
            _validatePrice(currentPrice, order.price),
            "Price outside range"
        );
        
        // Calculate amounts
        (uint256 outputAmount, uint256 fee) = _calculateAmounts(
            order.amountIn,
            currentPrice
        );
        
        // Execute trade
        IERC20(order.tokenOut).transfer(order.trader, outputAmount);
        
        // Update order
        order.status = OrderStatus.EXECUTED;
        order.amountOut = outputAmount;
        
        // Update stats
        _updateTradingStats(order.trader, order.amountIn, currentPrice, fee);
        
        emit OrderExecuted(orderId, currentPrice);
        emit TradeSettled(orderId, fee);
    }

    // Internal functions
    function _getCurrentPrice(
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _validatePrice(
        uint256 currentPrice,
        uint256 orderPrice
    ) internal pure returns (bool) {
        uint256 priceDiff = currentPrice > orderPrice ?
            currentPrice - orderPrice :
            orderPrice - currentPrice;
            
        return (priceDiff * 10000) / orderPrice <= MAX_SLIPPAGE;
    }

    function _calculateAmounts(
        uint256 inputAmount,
        uint256 price
    ) internal view returns (uint256 output, uint256 fee) {
        TradingConfig storage config = tradingConfigs[bytes32(0)]; // Default config
        
        fee = (inputAmount * config.tradingFee) / 10000;
        output = (inputAmount - fee) * price;
        
        return (output, fee);
    }

    function _updateTradingStats(
        address trader,
        uint256 amount,
        uint256 price,
        uint256 fee
    ) internal {
        TradingStats storage stats = tradingStats[trader];
        
        stats.totalVolume += amount;
        stats.totalTrades++;
        stats.avgPrice = (stats.avgPrice * (stats.totalTrades - 1) + price) / stats.totalTrades;
        stats.lastTrade = block.timestamp;
        stats.fees += fee;
    }

    // View functions
    function getOrder(
        bytes32 orderId
    ) external view returns (Order memory) {
        return orders[orderId];
    }

    function getTradingConfig(
        bytes32 configId
    ) external view returns (TradingConfig memory) {
        return tradingConfigs[configId];
    }

    function getTradingStats(
        address trader
    ) external view returns (TradingStats memory) {
        return tradingStats[trader];
    }

    function isTraderApproved(
        address trader
    ) external view returns (bool) {
        return approvedTraders[trader];
    }
} 