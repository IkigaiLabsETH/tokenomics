// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiNFT {
    function stake(uint256 amount) external;
    function withdrawStake(uint256 amount) external;
    function claimRewards() external;
    function getUserTier(address user) external view returns (uint256);
    function earned(address account) external view returns (uint256);
} 