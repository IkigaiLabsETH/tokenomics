// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiToken {
    // Events
    event Staked(address indexed user, uint256 amount, uint256 duration);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    // View functions
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stakedBalanceOf(address account) external view returns (uint256);
    function getRewardRate() external view returns (uint256);

    // State-changing functions
    function stake(uint256 amount, uint256 duration) external;
    function unstake(uint256 amount) external;
    function getReward() external;
    function emergencyUnstake() external;

    function mint(address to, uint256 amount) external;
    function burn(uint256 amount) external;
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
} 