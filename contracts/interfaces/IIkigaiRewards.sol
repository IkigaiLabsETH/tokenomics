// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiRewards {
    function updateReward(address account) external;
    function processSaleRewards(uint256 saleAmount) external;
    function earned(address account) external view returns (uint256);
    function getRewardStats() external view returns (
        uint256 totalDistributed,
        uint256 pending,
        uint256 lastDistribution,
        uint256 rewardPerToken
    );
} 