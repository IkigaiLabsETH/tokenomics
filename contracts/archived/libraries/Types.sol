// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Types {
    struct RewardConfig {
        uint256 rate;
        uint256 duration;
        uint256 totalAmount;
    }

    struct StakeInfo {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
    }
} 