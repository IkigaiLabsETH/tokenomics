// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IkigaiTokenV2.sol";

contract IkigaiTreasuryV2 is Ownable, ReentrancyGuard, Pausable {
    // Enhanced treasury allocation structure
    struct AllocationConfig {
        uint256 stakingPercent;      // Staking rewards allocation
        uint256 liquidityPercent;    // Protocol liquidity allocation
        uint256 operationsPercent;   // Operations allocation
        uint256 burnPercent;         // Token burn allocation
    }

    // Liquidity management structure
    struct LiquidityConfig {
        uint256 targetRatio;         // Target liquidity ratio (basis points)
        uint256 rebalanceThreshold;  // Threshold to trigger rebalance (basis points)
        uint256 minLiquidity;        // Minimum liquidity amount
        uint256 maxSlippage;         // Maximum allowed slippage (basis points)
    }

    // Revenue tracking
    struct RevenueSnapshot {
        uint256 timestamp;
        uint256 totalRevenue;
        uint256 stakingAmount;
        uint256 liquidityAmount;
        uint256 operationsAmount;
        uint256 burnAmount;
    }

    // State variables
    IkigaiTokenV2 public immutable ikigaiToken;
    IERC20 public immutable BERA;
    
    address public stakingPool;
    address public operationsWallet;
    address public liquidityPool;
    
    AllocationConfig public allocations;
    LiquidityConfig public liquidityConfig;
    
    mapping(uint256 => RevenueSnapshot) public revenueHistory;
    uint256 public currentSnapshotId;
    
    uint256 public totalRevenue;
    uint256 public lastRebalanceTime;
    
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_REBALANCE_INTERVAL = 1 days;
    uint256 public constant EMERGENCY_TIMELOCK = 24 hours;
    
    // Events
    event RevenueDistributed(
        uint256 indexed snapshotId,
        uint256 totalAmount,
        uint256 stakingAmount,
        uint256 liquidityAmount,
        uint256 operationsAmount,
        uint256 burnAmount
    );
    
    event LiquidityRebalanced(
        uint256 timestamp,
        uint256 addedLiquidity,
        uint256 removedLiquidity
    );
    
    event AllocationUpdated(
        uint256 stakingPercent,
        uint256 liquidityPercent,
        uint256 operationsPercent,
        uint256 burnPercent
    );
    
    event EmergencyWithdrawal(
        address indexed token,
        address indexed recipient,
        uint256 amount
    );

    constructor(
        address _ikigaiToken,
        address _bera,
        address _stakingPool,
        address _operationsWallet,
        address _liquidityPool
    ) Ownable(msg.sender) {
        ikigaiToken = IkigaiTokenV2(_ikigaiToken);
        BERA = IERC20(_bera);
        stakingPool = _stakingPool;
        operationsWallet = _operationsWallet;
        liquidityPool = _liquidityPool;
        
        // Initialize default allocations
        allocations = AllocationConfig({
            stakingPercent: 5000,    // 50%
            liquidityPercent: 3000,   // 30%
            operationsPercent: 1500,  // 15%
            burnPercent: 500         // 5%
        });
        
        // Initialize liquidity config
        liquidityConfig = LiquidityConfig({
            targetRatio: 2000,       // 20% target liquidity ratio
            rebalanceThreshold: 500,  // 5% threshold
            minLiquidity: 1000 ether, // 1000 tokens minimum
            maxSlippage: 100         // 1% max slippage
        });
    }

    // Core functions
    function distributeRevenue() external nonReentrant whenNotPaused {
        uint256 beraBalance = BERA.balanceOf(address(this));
        require(beraBalance > 0, "No revenue to distribute");
        
        // Calculate allocations
        uint256 stakingAmount = (beraBalance * allocations.stakingPercent) / BASIS_POINTS;
        uint256 liquidityAmount = (beraBalance * allocations.liquidityPercent) / BASIS_POINTS;
        uint256 operationsAmount = (beraBalance * allocations.operationsPercent) / BASIS_POINTS;
        uint256 burnAmount = (beraBalance * allocations.burnPercent) / BASIS_POINTS;
        
        // Create revenue snapshot
        currentSnapshotId++;
        revenueHistory[currentSnapshotId] = RevenueSnapshot({
            timestamp: block.timestamp,
            totalRevenue: beraBalance,
            stakingAmount: stakingAmount,
            liquidityAmount: liquidityAmount,
            operationsAmount: operationsAmount,
            burnAmount: burnAmount
        });
        
        // Distribute funds
        if (stakingAmount > 0) {
            require(BERA.transfer(stakingPool, stakingAmount), "Staking transfer failed");
        }
        
        if (liquidityAmount > 0) {
            require(BERA.transfer(liquidityPool, liquidityAmount), "Liquidity transfer failed");
        }
        
        if (operationsAmount > 0) {
            require(BERA.transfer(operationsWallet, operationsAmount), "Operations transfer failed");
        }
        
        if (burnAmount > 0) {
            require(BERA.transfer(address(0xdead), burnAmount), "Burn transfer failed");
        }
        
        totalRevenue += beraBalance;
        
        emit RevenueDistributed(
            currentSnapshotId,
            beraBalance,
            stakingAmount,
            liquidityAmount,
            operationsAmount,
            burnAmount
        );
    }

    function rebalanceLiquidity() external nonReentrant whenNotPaused {
        require(
            block.timestamp >= lastRebalanceTime + MIN_REBALANCE_INTERVAL,
            "Rebalance too frequent"
        );
        
        uint256 currentLiquidity = BERA.balanceOf(liquidityPool);
        uint256 targetLiquidity = (totalRevenue * liquidityConfig.targetRatio) / BASIS_POINTS;
        
        // Check if rebalance is needed
        uint256 difference;
        bool needsMore;
        
        if (currentLiquidity > targetLiquidity) {
            difference = currentLiquidity - targetLiquidity;
            needsMore = false;
        } else {
            difference = targetLiquidity - currentLiquidity;
            needsMore = true;
        }
        
        uint256 threshold = (targetLiquidity * liquidityConfig.rebalanceThreshold) / BASIS_POINTS;
        
        if (difference > threshold) {
            if (needsMore) {
                // Add liquidity
                require(
                    BERA.balanceOf(address(this)) >= difference,
                    "Insufficient balance for rebalance"
                );
                require(BERA.transfer(liquidityPool, difference), "Liquidity add failed");
                
                emit LiquidityRebalanced(block.timestamp, difference, 0);
            } else {
                // Remove excess liquidity
                require(
                    IERC20(liquidityPool).transfer(address(this), difference),
                    "Liquidity remove failed"
                );
                
                emit LiquidityRebalanced(block.timestamp, 0, difference);
            }
        }
        
        lastRebalanceTime = block.timestamp;
    }

    // Admin functions
    function updateAllocations(
        uint256 _stakingPercent,
        uint256 _liquidityPercent,
        uint256 _operationsPercent,
        uint256 _burnPercent
    ) external onlyOwner {
        require(
            _stakingPercent + _liquidityPercent + _operationsPercent + _burnPercent == BASIS_POINTS,
            "Invalid allocation"
        );
        
        allocations = AllocationConfig({
            stakingPercent: _stakingPercent,
            liquidityPercent: _liquidityPercent,
            operationsPercent: _operationsPercent,
            burnPercent: _burnPercent
        });
        
        emit AllocationUpdated(
            _stakingPercent,
            _liquidityPercent,
            _operationsPercent,
            _burnPercent
        );
    }

    function updateLiquidityConfig(
        uint256 _targetRatio,
        uint256 _rebalanceThreshold,
        uint256 _minLiquidity,
        uint256 _maxSlippage
    ) external onlyOwner {
        require(_targetRatio <= 5000, "Target ratio too high"); // Max 50%
        require(_rebalanceThreshold <= 1000, "Threshold too high"); // Max 10%
        require(_maxSlippage <= 500, "Slippage too high"); // Max 5%
        
        liquidityConfig = LiquidityConfig({
            targetRatio: _targetRatio,
            rebalanceThreshold: _rebalanceThreshold,
            minLiquidity: _minLiquidity,
            maxSlippage: _maxSlippage
        });
    }

    // Emergency functions
    function emergencyWithdraw(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        require(paused(), "Only when paused");
        require(recipient != address(0), "Invalid recipient");
        
        IERC20 tokenContract = IERC20(token);
        require(
            tokenContract.transfer(recipient, amount),
            "Emergency withdrawal failed"
        );
        
        emit EmergencyWithdrawal(token, recipient, amount);
    }

    // View functions
    function getRevenueSnapshot(
        uint256 snapshotId
    ) external view returns (RevenueSnapshot memory) {
        return revenueHistory[snapshotId];
    }

    function getLiquidityStatus() external view returns (
        uint256 currentLiquidity,
        uint256 targetLiquidity,
        uint256 difference,
        bool needsRebalance
    ) {
        currentLiquidity = BERA.balanceOf(liquidityPool);
        targetLiquidity = (totalRevenue * liquidityConfig.targetRatio) / BASIS_POINTS;
        
        if (currentLiquidity > targetLiquidity) {
            difference = currentLiquidity - targetLiquidity;
        } else {
            difference = targetLiquidity - currentLiquidity;
        }
        
        uint256 threshold = (targetLiquidity * liquidityConfig.rebalanceThreshold) / BASIS_POINTS;
        needsRebalance = difference > threshold;
    }
} 