// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiRewards {
    event RewardAdded(uint256 reward);
    event RewardPaid(address indexed user, uint256 reward);
    event ComboIncreased(address indexed user, uint256 newCombo);
    event ComboReset(address indexed user);

    function getRewardForUser(address user) external view returns (uint256);
    function getUserCombo(address user) external view returns (uint256 combo, uint256 lastAction);
    function claimReward() external;
} 