// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Constants {
    // Basis points
    uint256 constant BASIS_POINTS = 10000;
    
    // Fees
    uint256 constant MAX_FEE = 2000;        // 20%
    uint256 constant MIN_FEE = 50;          // 0.5%
    
    // Time constants
    uint256 constant MIN_LOCK_PERIOD = 1 days;
    uint256 constant MAX_LOCK_PERIOD = 365 days;
    
    // Limits
    uint256 constant MAX_MINT_PER_TX = 20;
    uint256 constant MAX_STAKE_AMOUNT = 1_000_000 * 1e18;
} 