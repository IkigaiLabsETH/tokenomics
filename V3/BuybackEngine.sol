// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title BuybackEngine
 * @notice Manages automated buybacks, revenue streams, and token burns for Ikigai V2
 * @dev Implements dynamic pressure system and strategic allocation
 */
contract BuybackEngine is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant REVENUE_SOURCE_ROLE = keccak256("REVENUE_SOURCE_ROLE");

    // Token references
    IERC20 public immutable ikigaiToken;
    IERC20 public immutable stablecoin;
    AggregatorV3Interface public priceFeed;

    // Buyback parameters
    uint256 public constant BURN_RATIO = 8000;           // 80% of buybacks are burned
    uint256 public constant REWARD_POOL_RATIO = 2000;    // 20% to rewards pool
    uint256 public constant MIN_BUYBACK_AMOUNT = 100e18; // Minimum buyback size
    uint256 public constant PRICE_DECIMALS = 8;          // Chainlink price decimals

    // Pressure system parameters
    uint256 public constant BASE_PRESSURE = 5000;        // 50% base buyback pressure
    uint256 public constant MAX_PRESSURE = 8000;         // 80% max buyback pressure
    uint256 public constant PRESSURE_INCREASE_RATE = 500; // 5% increase per level
    uint256 public constant PRESSURE_LEVELS = 6;         // Number of pressure levels

    // Revenue distribution
    uint256 public constant NFT_SALES_BUYBACK = 3000;    // 30% of NFT sales
    uint256 public constant PLATFORM_FEES_BUYBACK = 2500; // 25% of platform fees
    uint256 public constant TREASURY_YIELD_BUYBACK = 2000;// 20% of treasury yield

    // Cooldown and thresholds
    uint256 public constant BUYBACK_COOLDOWN = 1 days;
    uint256 public lastBuybackTime;
    uint256 public accumulatedFunds;

    // Price thresholds
    struct PriceThreshold {
        uint256 price;
        uint256 pressureLevel;
        bool active;
    }
    PriceThreshold[] public priceThresholds;

    // Revenue tracking
    struct RevenueStream {
        uint256 totalCollected;
        uint256 lastUpdate;
        uint256 buybackAllocation;
    }
    mapping(bytes32 => RevenueStream) public revenueStreams;

    // Events
    event BuybackExecuted(
        uint256 amount,
        uint256 tokensBought,
        uint256 tokensBurned,
        uint256 tokensToRewards
    );
    event RevenueCollected(
        bytes32 indexed source,
        uint256 amount,
        uint256 buybackAllocation
    );
    event PriceThresholdUpdated(
        uint256 indexed level,
        uint256 price,
        uint256 pressureLevel
    );
    event PressureSystemUpdated(
        uint256 baseLevel,
        uint256 currentPressure
    );

    constructor(
        address _ikigaiToken,
        address _stablecoin,
        address _priceFeed,
        address _admin
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        stablecoin = IERC20(_stablecoin);
        priceFeed = AggregatorV3Interface(_priceFeed);

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
        _setupRole(OPERATOR_ROLE, _admin);

        // Initialize price thresholds
        priceThresholds.push(PriceThreshold({
            price: 0.5e8,  // $0.50
            pressureLevel: 1,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.4e8,  // $0.40
            pressureLevel: 2,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.3e8,  // $0.30
            pressureLevel: 3,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.2e8,  // $0.20
            pressureLevel: 4,
            active: true
        }));
        priceThresholds.push(PriceThreshold({
            price: 0.1e8,  // $0.10
            pressureLevel: 5,
            active: true
        }));
    }

    /**
     * @notice Collects revenue from various sources and allocates to buyback pool
     * @param source Identifier for the revenue source
     * @param amount Amount of stablecoin collected
     */
    function collectRevenue(bytes32 source, uint256 amount) external nonReentrant {
        require(hasRole(REVENUE_SOURCE_ROLE, msg.sender), "Not authorized");
        require(amount > 0, "Invalid amount");

        RevenueStream storage stream = revenueStreams[source];
        uint256 buybackShare;

        // Calculate buyback allocation based on source
        if (source == keccak256("NFT_SALES")) {
            buybackShare = (amount * NFT_SALES_BUYBACK) / 10000;
        } else if (source == keccak256("PLATFORM_FEES")) {
            buybackShare = (amount * PLATFORM_FEES_BUYBACK) / 10000;
        } else if (source == keccak256("TREASURY_YIELD")) {
            buybackShare = (amount * TREASURY_YIELD_BUYBACK) / 10000;
        } else {
            revert("Invalid revenue source");
        }

        // Transfer revenue
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);

        // Update stream stats
        stream.totalCollected += amount;
        stream.lastUpdate = block.timestamp;
        stream.buybackAllocation += buybackShare;
        accumulatedFunds += buybackShare;

        emit RevenueCollected(source, amount, buybackShare);

        // Try to execute buyback if enough funds
        if (accumulatedFunds >= MIN_BUYBACK_AMOUNT) {
            _executeBuyback();
        }
    }

    /**
     * @notice Executes buyback based on current market conditions and pressure system
     */
    function executeBuyback() external nonReentrant {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not authorized");
        require(block.timestamp >= lastBuybackTime + BUYBACK_COOLDOWN, "Cooldown active");
        require(accumulatedFunds >= MIN_BUYBACK_AMOUNT, "Insufficient funds");

        _executeBuyback();
    }

    /**
     * @notice Internal function to execute buyback
     */
    function _executeBuyback() internal {
        uint256 amount = accumulatedFunds;
        uint256 currentPrice = getCurrentPrice();
        uint256 pressure = calculatePressure(currentPrice);
        
        // Calculate buyback amount based on pressure
        uint256 buybackAmount = (amount * pressure) / 10000;
        
        // Execute market buy (implement DEX integration here)
        uint256 tokensBought = executeMarketBuy(buybackAmount);
        
        // Distribute bought tokens
        uint256 tokensToBurn = (tokensBought * BURN_RATIO) / 10000;
        uint256 tokensToRewards = tokensBought - tokensToBurn;
        
        // Burn tokens
        ikigaiToken.transfer(address(0xdead), tokensToBurn);
        
        // Send to rewards pool
        address rewardsPool = getRewardsPool(); // Implement this
        ikigaiToken.transfer(rewardsPool, tokensToRewards);
        
        // Update state
        accumulatedFunds -= buybackAmount;
        lastBuybackTime = block.timestamp;
        
        emit BuybackExecuted(
            buybackAmount,
            tokensBought,
            tokensToBurn,
            tokensToRewards
        );
    }

    /**
     * @notice Calculates current buyback pressure based on price
     * @param currentPrice Current token price
     * @return uint256 Pressure level (5000-8000 = 50-80%)
     */
    function calculatePressure(uint256 currentPrice) public view returns (uint256) {
        uint256 pressureLevel = BASE_PRESSURE;
        
        for (uint i = 0; i < priceThresholds.length; i++) {
            if (priceThresholds[i].active && 
                currentPrice <= priceThresholds[i].price) {
                pressureLevel += PRESSURE_INCREASE_RATE * priceThresholds[i].pressureLevel;
            }
        }
        
        return pressureLevel > MAX_PRESSURE ? MAX_PRESSURE : pressureLevel;
    }

    /**
     * @notice Gets current token price from Chainlink
     */
    function getCurrentPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    /**
     * @notice Executes market buy order (placeholder for DEX integration)
     * @param amount Amount of stablecoin to spend
     * @return uint256 Amount of tokens bought
     */
    function executeMarketBuy(uint256 amount) internal returns (uint256) {
        // Implement DEX integration here
        // For now, return a dummy value
        return amount * 1e18 / getCurrentPrice();
    }

    /**
     * @notice Updates price thresholds for the pressure system
     * @param level Threshold level to update
     * @param price New price threshold
     * @param pressureLevel New pressure level
     * @param active Whether the threshold is active
     */
    function updatePriceThreshold(
        uint256 level,
        uint256 price,
        uint256 pressureLevel,
        bool active
    ) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not admin");
        require(level < priceThresholds.length, "Invalid level");
        require(pressureLevel <= PRESSURE_LEVELS, "Invalid pressure");

        priceThresholds[level] = PriceThreshold({
            price: price,
            pressureLevel: pressureLevel,
            active: active
        });

        emit PriceThresholdUpdated(level, price, pressureLevel);
    }

    // Emergency functions
    function pause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        _pause();
    }

    function unpause() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Not operator");
        _unpause();
    }

    // View functions
    function getRevenueStream(bytes32 source) external view returns (
        uint256 totalCollected,
        uint256 lastUpdate,
        uint256 buybackAllocation
    ) {
        RevenueStream memory stream = revenueStreams[source];
        return (
            stream.totalCollected,
            stream.lastUpdate,
            stream.buybackAllocation
        );
    }

    function getPriceThresholds() external view returns (PriceThreshold[] memory) {
        return priceThresholds;
    }

    function getRewardsPool() internal view returns (address) {
        // Implement rewards pool address retrieval
        return address(0x123); // Placeholder
    }
} 