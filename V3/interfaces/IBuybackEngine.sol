// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IBuybackEngine
 * @notice Interface for the Ikigai V2 buyback engine
 * @dev Handles revenue collection, buybacks, and token burns
 */
interface IBuybackEngine {
    struct LiquidityDepth {
        uint256 price;
        uint256 volume;
        uint256 impact;
        bool sufficient;
    }

    /**
     * @notice Structure for price threshold configuration
     */
    struct PriceThreshold {
        uint256 price;
        uint256 pressureLevel;
        bool active;
    }

    /**
     * @notice Structure for revenue stream tracking
     */
    struct RevenueStream {
        uint256 totalCollected;
        uint256 lastUpdate;
        uint256 buybackAllocation;
    }

    /**
     * @notice Collects revenue from various sources
     * @param source Revenue source identifier
     * @param amount Amount of stablecoin collected
     */
    function collectRevenue(bytes32 source, uint256 amount) external;

    /**
     * @notice Manually triggers a buyback operation
     */
    function executeBuyback() external;

    /**
     * @notice Calculates current buyback pressure
     * @param currentPrice Current token price
     * @return uint256 Pressure level (5000-8000 = 50-80%)
     */
    function calculatePressure(uint256 currentPrice) external view returns (uint256);

    /**
     * @notice Gets current token price
     * @return uint256 Current price from Chainlink
     */
    function getCurrentPrice() external view returns (uint256);

    /**
     * @notice Updates price threshold configuration
     * @param level Threshold level to update
     * @param price New price threshold
     * @param pressureLevel New pressure level
     * @param active Whether threshold is active
     */
    function updatePriceThreshold(
        uint256 level,
        uint256 price,
        uint256 pressureLevel,
        bool active
    ) external;

    /**
     * @notice Gets revenue stream information
     * @param source Revenue source identifier
     * @return totalCollected Total revenue collected
     * @return lastUpdate Last update timestamp
     * @return buybackAllocation Amount allocated to buybacks
     */
    function getRevenueStream(bytes32 source) external view returns (
        uint256 totalCollected,
        uint256 lastUpdate,
        uint256 buybackAllocation
    );

    /**
     * @notice Gets all price thresholds
     * @return PriceThreshold[] Array of price thresholds
     */
    function getPriceThresholds() external view returns (PriceThreshold[] memory);

    /**
     * @notice Pauses buyback operations
     */
    function pause() external;

    /**
     * @notice Resumes buyback operations
     */
    function unpause() external;

    // Analysis functions
    function analyzeLiquidityDepth(uint256 amount) external view returns (LiquidityDepth[] memory);
    function calculateOptimalBuyback(uint256 amount) external view returns (uint256);
    function checkPriceImpact(uint256 amount) external view returns (bool);

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
} 