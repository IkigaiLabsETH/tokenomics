// In TreasuryV2.sol

// Modify the allocation config
struct AllocationConfig {
    uint256 stakingPercent;      // Increased to 55%
    uint256 liquidityPercent;    // Maintained at 30%
    uint256 operationsPercent;   // Increased to 13%
    uint256 burnPercent;         // Reduced to 2%
    uint256 burnThreshold;       // Price threshold for burns
    bool burnEnabled;            // Can disable burns if needed
}

// Add dynamic burn adjustment
function shouldExecuteBurn() internal view returns (bool) {
    if (!allocations.burnEnabled) return false;
    
    // Only burn if price is above threshold
    return ikigaiToken.averagePrice() >= allocations.burnThreshold;
}

// Modify distributeRevenue function
function distributeRevenue() external nonReentrant whenNotPaused {
    // ... existing code ...

    uint256 burnAmount = shouldExecuteBurn() ? 
        (beraBalance * allocations.burnPercent) / BASIS_POINTS : 0;

    if (burnAmount > 0) {
        stakingAmount += burnAmount / 2;    // Redistribute half to staking
        liquidityAmount += burnAmount / 2;  // Half to liquidity
    }

    // ... rest of the function ...
} 