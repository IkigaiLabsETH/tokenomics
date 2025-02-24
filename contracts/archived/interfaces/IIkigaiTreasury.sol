// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiTreasury {
    function addLiquidity(uint256 beraAmount) external;
    function rebalance() external;
    function getCurrentRatio() external view returns (uint256);
    function getTreasuryStats() external view returns (
        uint256 totalBERA,
        uint256 totalIkigai,
        uint256 pendingFees,
        uint256 liquidityRatio
    );
} 