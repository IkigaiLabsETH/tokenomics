// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IIkigaiTreasuryV2.sol";
import "./interfaces/IIkigaiLiquidityV2.sol";

contract IkigaiVaultV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant VAULT_MANAGER = keccak256("VAULT_MANAGER");
    bytes32 public constant STRATEGY_ROLE = keccak256("STRATEGY_ROLE");

    struct VaultStrategy {
        bool isActive;
        uint256 allocationShare;    // Share of vault assets (basis points)
        uint256 performanceFee;     // Fee on profits (basis points)
        uint256 managementFee;      // Annual management fee (basis points)
        uint256 totalDeposited;
        uint256 totalWithdrawn;
        uint256 lastRebalance;
    }

    struct AssetConfig {
        bool isSupported;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 withdrawalDelay;
        uint256 rebalanceThreshold;
        bool requiresWhitelist;
    }

    struct StrategyPerformance {
        uint256 totalProfit;
        uint256 totalLoss;
        uint256 highWaterMark;
        uint256 lastReport;
        uint256 performancePeriod;
    }

    // State variables
    mapping(address => mapping(address => VaultStrategy)) public strategies; // token => strategy => config
    mapping(address => AssetConfig) public assets;
    mapping(address => StrategyPerformance) public performance;
    mapping(address => bool) public whitelist;
    
    uint256 public constant MAX_STRATEGIES_PER_ASSET = 5;
    uint256 public constant MAX_TOTAL_ALLOCATION = 8000; // 80% max in strategies
    uint256 public constant REBALANCE_INTERVAL = 1 days;
    uint256 public constant PERFORMANCE_PERIOD = 30 days;
    
    IIkigaiTreasuryV2 public treasury;
    IIkigaiLiquidityV2 public liquidityManager;

    // Events
    event StrategyAdded(address indexed token, address indexed strategy, uint256 allocation);
    event StrategyUpdated(address indexed token, address indexed strategy, uint256 newAllocation);
    event AssetsDeposited(address indexed token, address indexed strategy, uint256 amount);
    event AssetsWithdrawn(address indexed token, address indexed strategy, uint256 amount);
    event PerformanceReported(address indexed strategy, uint256 profit, uint256 loss);
    event RebalanceExecuted(address indexed token, uint256 timestamp);

    constructor(address _treasury, address _liquidityManager) {
        treasury = IIkigaiTreasuryV2(_treasury);
        liquidityManager = IIkigaiLiquidityV2(_liquidityManager);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Strategy management
    function addStrategy(
        address token,
        address strategy,
        uint256 allocation,
        uint256 performanceFee,
        uint256 managementFee
    ) external onlyRole(VAULT_MANAGER) {
        require(assets[token].isSupported, "Asset not supported");
        require(!strategies[token][strategy].isActive, "Strategy exists");
        require(performanceFee <= 2000, "Performance fee too high"); // Max 20%
        require(managementFee <= 500, "Management fee too high"); // Max 5%
        
        uint256 totalAllocation = getTotalAllocation(token);
        require(totalAllocation + allocation <= MAX_TOTAL_ALLOCATION, "Allocation too high");
        
        strategies[token][strategy] = VaultStrategy({
            isActive: true,
            allocationShare: allocation,
            performanceFee: performanceFee,
            managementFee: managementFee,
            totalDeposited: 0,
            totalWithdrawn: 0,
            lastRebalance: block.timestamp
        });
        
        emit StrategyAdded(token, strategy, allocation);
    }

    // Asset deposits and withdrawals
    function depositToStrategy(
        address token,
        address strategy,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(STRATEGY_ROLE) {
        VaultStrategy storage strat = strategies[token][strategy];
        require(strat.isActive, "Strategy not active");
        require(
            block.timestamp >= strat.lastRebalance + REBALANCE_INTERVAL,
            "Too soon to rebalance"
        );
        
        IERC20 asset = IERC20(token);
        require(
            asset.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        strat.totalDeposited += amount;
        strat.lastRebalance = block.timestamp;
        
        emit AssetsDeposited(token, strategy, amount);
    }

    function withdrawFromStrategy(
        address token,
        address strategy,
        uint256 amount
    ) external nonReentrant onlyRole(STRATEGY_ROLE) {
        VaultStrategy storage strat = strategies[token][strategy];
        require(strat.isActive, "Strategy not active");
        
        AssetConfig storage config = assets[token];
        require(
            !config.requiresWhitelist || whitelist[msg.sender],
            "Not whitelisted"
        );
        
        IERC20 asset = IERC20(token);
        require(
            asset.transfer(msg.sender, amount),
            "Transfer failed"
        );
        
        strat.totalWithdrawn += amount;
        
        emit AssetsWithdrawn(token, strategy, amount);
    }

    // Performance reporting
    function reportPerformance(
        address strategy,
        uint256 profit,
        uint256 loss
    ) external onlyRole(STRATEGY_ROLE) {
        StrategyPerformance storage perf = performance[strategy];
        
        // Update performance metrics
        if (block.timestamp >= perf.lastReport + PERFORMANCE_PERIOD) {
            // Reset for new period
            perf.totalProfit = profit;
            perf.totalLoss = loss;
            perf.performancePeriod++;
        } else {
            perf.totalProfit += profit;
            perf.totalLoss += loss;
        }
        
        // Update high water mark
        if (profit > loss && (profit - loss) > perf.highWaterMark) {
            perf.highWaterMark = profit - loss;
        }
        
        perf.lastReport = block.timestamp;
        
        emit PerformanceReported(strategy, profit, loss);
    }

    // Rebalancing
    function rebalanceStrategy(
        address token,
        address strategy
    ) external nonReentrant whenNotPaused onlyRole(VAULT_MANAGER) {
        VaultStrategy storage strat = strategies[token][strategy];
        require(strat.isActive, "Strategy not active");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 targetAmount = (balance * strat.allocationShare) / 10000;
        uint256 currentAmount = strat.totalDeposited - strat.totalWithdrawn;
        
        if (Math.abs(int256(targetAmount - currentAmount)) > assets[token].rebalanceThreshold) {
            if (targetAmount > currentAmount) {
                uint256 depositAmount = targetAmount - currentAmount;
                depositToStrategy(token, strategy, depositAmount);
            } else {
                uint256 withdrawAmount = currentAmount - targetAmount;
                withdrawFromStrategy(token, strategy, withdrawAmount);
            }
        }
        
        emit RebalanceExecuted(token, block.timestamp);
    }

    // View functions
    function getTotalAllocation(
        address token
    ) public view returns (uint256 total) {
        for (uint256 i = 0; i < MAX_STRATEGIES_PER_ASSET; i++) {
            address strategy = getStrategyAtIndex(token, i);
            if (strategy == address(0)) break;
            
            if (strategies[token][strategy].isActive) {
                total += strategies[token][strategy].allocationShare;
            }
        }
        return total;
    }

    function getStrategyAtIndex(
        address token,
        uint256 index
    ) public view returns (address) {
        // Implementation needed
        return address(0);
    }

    function getStrategyPerformance(
        address strategy
    ) external view returns (
        uint256 totalProfit,
        uint256 totalLoss,
        uint256 highWaterMark,
        uint256 currentPeriod
    ) {
        StrategyPerformance storage perf = performance[strategy];
        return (
            perf.totalProfit,
            perf.totalLoss,
            perf.highWaterMark,
            perf.performancePeriod
        );
    }
} 