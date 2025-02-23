// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiLiquidityV2.sol";

/**
 * @title IkigaiYieldStrategyV2
 * @notice Yield farming strategy for Ikigai protocol assets
 */
contract IkigaiYieldStrategyV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant STRATEGY_MANAGER = keccak256("STRATEGY_MANAGER");
    bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

    struct StrategyParams {
        uint256 targetLeverage;     // Target leverage ratio (basis points)
        uint256 minYield;           // Minimum acceptable yield (basis points)
        uint256 maxDrawdown;        // Maximum allowed drawdown (basis points)
        uint256 rebalanceThreshold; // Threshold to trigger rebalance
        uint256 harvestInterval;    // Minimum time between harvests
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

    // State variables
    IIkigaiVaultV2 public immutable vault;
    IIkigaiLiquidityV2 public immutable liquidityManager;
    IERC20 public immutable asset;
    
    StrategyParams public params;
    Position public currentPosition;
    HarvestStats public harvestStats;
    
    uint256 public totalValueLocked;
    uint256 public highWaterMark;
    
    // Constants
    uint256 public constant MAX_LEVERAGE = 3000; // 3x leverage
    uint256 public constant MIN_HARVEST_INTERVAL = 6 hours;
    uint256 public constant EMERGENCY_EXIT_DELAY = 6 hours;
    
    // Events
    event PositionOpened(uint256 principal, uint256 borrowed, uint256 collateral);
    event PositionClosed(uint256 principal, uint256 profit, uint256 loss);
    event Harvested(uint256 amount, uint256 yield, uint256 timestamp);
    event ParamsUpdated(string param, uint256 value);
    event EmergencyExit(uint256 timestamp, string reason);

    constructor(
        address _vault,
        address _liquidityManager,
        address _asset
    ) {
        vault = IIkigaiVaultV2(_vault);
        liquidityManager = IIkigaiLiquidityV2(_liquidityManager);
        asset = IERC20(_asset);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize strategy parameters
        params = StrategyParams({
            targetLeverage: 1500,    // 1.5x leverage
            minYield: 500,           // 5% minimum yield
            maxDrawdown: 1000,       // 10% maximum drawdown
            rebalanceThreshold: 200, // 2% rebalance threshold
            harvestInterval: 1 days  // Daily harvests
        });
    }

    // Core strategy functions
    function openPosition(
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(STRATEGY_MANAGER) {
        require(amount > 0, "Invalid amount");
        require(!currentPosition.isActive, "Position exists");
        
        // Calculate leverage and borrowing
        uint256 borrowAmount = (amount * params.targetLeverage) / 10000;
        uint256 totalCollateral = amount + borrowAmount;
        
        // Transfer assets from vault
        require(
            asset.transferFrom(address(vault), address(this), amount),
            "Transfer failed"
        );
        
        // Update position
        currentPosition = Position({
            principal: amount,
            borrowed: borrowAmount,
            collateral: totalCollateral,
            lastUpdate: block.timestamp,
            entryPrice: getAssetPrice(),
            isActive: true
        });
        
        totalValueLocked += amount;
        
        emit PositionOpened(amount, borrowAmount, totalCollateral);
    }

    function closePosition() 
        external 
        nonReentrant 
        onlyRole(STRATEGY_MANAGER) 
    {
        require(currentPosition.isActive, "No position");
        
        uint256 currentValue = getCurrentValue();
        uint256 profit = 0;
        uint256 loss = 0;
        
        if (currentValue > currentPosition.principal) {
            profit = currentValue - currentPosition.principal;
        } else {
            loss = currentPosition.principal - currentValue;
        }
        
        // Repay borrowed amount
        _repayBorrowed(currentPosition.borrowed);
        
        // Transfer remaining value back to vault
        require(
            asset.transfer(address(vault), currentValue),
            "Transfer failed"
        );
        
        // Update stats
        totalValueLocked -= currentPosition.principal;
        
        // Reset position
        delete currentPosition;
        
        emit PositionClosed(currentPosition.principal, profit, loss);
        
        // Report performance to vault
        vault.reportPerformance(address(this), profit, loss);
    }

    function harvest() 
        external 
        nonReentrant 
        whenNotPaused 
        onlyRole(HARVESTER_ROLE) 
    {
        require(
            block.timestamp >= harvestStats.lastHarvestTime + params.harvestInterval,
            "Too soon to harvest"
        );
        
        uint256 balanceBefore = asset.balanceOf(address(this));
        
        // Claim rewards and convert to asset
        _claimAndConvertRewards();
        
        uint256 harvestedAmount = asset.balanceOf(address(this)) - balanceBefore;
        require(harvestedAmount > 0, "Nothing to harvest");
        
        // Calculate yield
        uint256 yield = (harvestedAmount * 10000) / totalValueLocked;
        require(yield >= params.minYield, "Yield too low");
        
        // Update harvest stats
        harvestStats.totalHarvested += harvestedAmount;
        harvestStats.lastHarvestYield = yield;
        harvestStats.bestYield = Math.max(harvestStats.bestYield, yield);
        harvestStats.worstYield = harvestStats.worstYield == 0 ? 
            yield : Math.min(harvestStats.worstYield, yield);
        harvestStats.harvestCount++;
        harvestStats.lastHarvestTime = block.timestamp;
        
        emit Harvested(harvestedAmount, yield, block.timestamp);
    }

    // Internal functions
    function _claimAndConvertRewards() internal {
        // Implementation needed for specific yield source
    }

    function _repayBorrowed(uint256 amount) internal {
        // Implementation needed for borrowing source
    }

    // Risk management
    function checkHealth() public view returns (bool healthy, string memory reason) {
        if (!currentPosition.isActive) {
            return (true, "No active position");
        }
        
        uint256 currentPrice = getAssetPrice();
        uint256 priceDrop = currentPosition.entryPrice > currentPrice ? 
            ((currentPosition.entryPrice - currentPrice) * 10000) / currentPosition.entryPrice : 0;
            
        if (priceDrop >= params.maxDrawdown) {
            return (false, "Max drawdown exceeded");
        }
        
        uint256 collateralRatio = (currentPosition.collateral * 10000) / currentPosition.borrowed;
        if (collateralRatio < 12000) { // 120% minimum collateral ratio
            return (false, "Collateral ratio too low");
        }
        
        return (true, "Position healthy");
    }

    function emergencyExit(string memory reason) 
        external 
        onlyRole(STRATEGY_MANAGER) 
    {
        _pause();
        closePosition();
        emit EmergencyExit(block.timestamp, reason);
    }

    // View functions
    function getCurrentValue() public view returns (uint256) {
        if (!currentPosition.isActive) return 0;
        
        uint256 currentPrice = getAssetPrice();
        return (currentPosition.collateral * currentPrice) / currentPosition.entryPrice;
    }

    function getAssetPrice() public view returns (uint256) {
        // Implementation needed for price feed
        return 0;
    }

    function getStrategyStats() external view returns (
        uint256 tvl,
        uint256 apy,
        uint256 leverage,
        bool isActive,
        uint256 lastHarvest
    ) {
        return (
            totalValueLocked,
            harvestStats.lastHarvestYield * 365, // Annualized yield
            currentPosition.isActive ? 
                (currentPosition.collateral * 10000) / currentPosition.principal : 0,
            currentPosition.isActive,
            harvestStats.lastHarvestTime
        );
    }
} 