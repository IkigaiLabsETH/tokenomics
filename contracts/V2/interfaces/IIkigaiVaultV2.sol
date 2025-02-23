// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIkigaiVaultV2 {
    struct VaultStrategy {
        bool isActive;
        uint256 allocationShare;
        uint256 performanceFee;
        uint256 managementFee;
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 lastRebalance;
    }

    struct AssetConfig {
        bool isSupported;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 withdrawalDelay;
        uint256 rebalanceThreshold;
        bool requiresWhitelist;
    }

    struct StrategyPerformance {
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 highWaterMark;
        uint256 lastReport;
        uint256 performancePeriod;
    }

    // View functions
    function strategies(address token, address strategy) external view returns (VaultStrategy memory);
    function assets(address token) external view returns (AssetConfig memory);
    function performance(address strategy) external view returns (StrategyPerformance memory);
    function getTotalAllocation(address token) external view returns (uint256);
    function getStrategyPerformance(address strategy) external view returns (
        uint256 totalProfit,
        uint256 totalLoss,
        uint256 highWaterMark,
        uint256 currentPeriod
    );

    // State-changing functions
    function depositToStrategy(address token, address strategy, uint256 amount) external;
    function withdrawFromStrategy(address token, address strategy, uint256 amount) external;
    function reportPerformance(address strategy, uint256 profit, uint256 loss) external;
    function rebalanceStrategy(address token, address strategy) external;

    // Events
    event StrategyAdded(address indexed token, address indexed strategy, uint256 allocation);
    event StrategyUpdated(address indexed token, address indexed strategy, uint256 newAllocation);
    event AssetsDeposited(address indexed token, address indexed strategy, uint256 amount);
    event AssetsWithdrawn(address indexed token, address indexed strategy, uint256 amount);
    event PerformanceReported(address indexed strategy, uint256 profit, uint256 loss);
    event RebalanceExecuted(address indexed token, uint256 timestamp);
} 