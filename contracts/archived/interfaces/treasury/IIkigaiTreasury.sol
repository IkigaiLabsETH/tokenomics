// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIkigaiTreasury {
    event FundsDeposited(address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event RewardDistributed(address indexed token, uint256 amount);

    function deposit(address token, uint256 amount) external;
    function withdraw(address token, address to, uint256 amount) external;
    function distributeRewards() external;
} 