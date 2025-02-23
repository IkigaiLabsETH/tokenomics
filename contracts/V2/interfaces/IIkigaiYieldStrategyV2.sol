// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIkigaiYieldStrategyV2 {
    struct StrategyParams {
        uint256 targetLeverage;
        uint256 minYield;
        uint256 maxDrawdown;
        uint256 rebalanceThreshold;
        uint256 harvestInterval;
    }

    struct Position {
        uint256 principal;
        uint256 borrowed;
        uint256 collateral;
        uint256 lastUpdate;
        uint256 entryPrice;
        bool isActive;
    }

    struct HarvestStats {
        uint256 totalHarvested;
        uint256 lastHarvestYield;
        uint256 bestYield;
        uint256 worstYield;
        uint256 harvestCount;
        uint256 lastHarvestTime;
    }

    // View functions
    function getCurrentValue() external view returns (uint256);
    function getAssetPrice() external view returns (uint256);
    function checkHealth() external view returns (bool healthy, string memory reason);
    function getStrategyStats() external view returns (
        uint256 tvl,
        uint256 apy,
        uint256 leverage,
        bool isActive,
        uint256 lastHarvest
    );

    // State-changing functions
    function openPosition(uint256 amount) external;
    function closePosition() external;
    function harvest() external;
    function emergencyExit(string memory reason) external;

    // Events
    event PositionOpened(uint256 principal, uint256 borrowed, uint256 collateral);
    event PositionClosed(uint256 principal, uint256 profit, uint256 loss);
    event Harvested(uint256 amount, uint256 yield, uint256 timestamp);
    event ParamsUpdated(string param, uint256 value);
    event EmergencyExit(uint256 timestamp, string reason);
} 