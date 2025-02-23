// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract IkigaiLiquidityV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant REBALANCER_ROLE = keccak256("REBALANCER_ROLE");

    struct LiquidityConfig {
        uint256 targetRatio;        // Target liquidity ratio (basis points)
        uint256 rebalanceThreshold; // Threshold to trigger rebalance
        uint256 maxSlippage;        // Maximum allowed slippage
        uint256 minLiquidity;       // Minimum liquidity to maintain
        uint256 rebalanceInterval;  // Minimum time between rebalances
    }

    struct LiquiditySnapshot {
        uint256 timestamp;
        uint256 totalLiquidity;
        uint256 ikigaiReserve;
        uint256 beraReserve;
        uint256 lpTokens;
        uint256 price;
    }

    // State variables
    IUniswapV2Router02 public immutable router;
    IUniswapV2Pair public immutable pair;
    IERC20 public immutable ikigaiToken;
    IERC20 public immutable BERA;
    
    LiquidityConfig public config;
    mapping(uint256 => LiquiditySnapshot) public snapshots;
    uint256 public lastSnapshotId;
    uint256 public lastRebalanceTime;
    
    // Events
    event LiquidityAdded(uint256 ikigaiAmount, uint256 beraAmount, uint256 lpTokens);
    event LiquidityRemoved(uint256 ikigaiAmount, uint256 beraAmount, uint256 lpTokens);
    event RebalanceExecuted(uint256 timestamp, string reason);
    event ConfigUpdated(string parameter, uint256 value);
    event SnapshotCreated(uint256 indexed id, uint256 timestamp);

    constructor(
        address _router,
        address _pair,
        address _ikigaiToken,
        address _bera
    ) {
        router = IUniswapV2Router02(_router);
        pair = IUniswapV2Pair(_pair);
        ikigaiToken = IERC20(_ikigaiToken);
        BERA = IERC20(_bera);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize config
        config = LiquidityConfig({
            targetRatio: 2000,      // 20% target ratio
            rebalanceThreshold: 500, // 5% threshold
            maxSlippage: 100,       // 1% max slippage
            minLiquidity: 1000 ether, // 1000 tokens min
            rebalanceInterval: 1 days // Daily rebalancing
        });
    }

    // Core liquidity functions
    function addLiquidity(
        uint256 ikigaiAmount,
        uint256 beraAmount
    ) external nonReentrant whenNotPaused onlyRole(MANAGER_ROLE) {
        require(
            ikigaiToken.transferFrom(msg.sender, address(this), ikigaiAmount),
            "IKIGAI transfer failed"
        );
        require(
            BERA.transferFrom(msg.sender, address(this), beraAmount),
            "BERA transfer failed"
        );

        ikigaiToken.approve(address(router), ikigaiAmount);
        BERA.approve(address(router), beraAmount);

        (uint256 amountIkigai, uint256 amountBera, uint256 liquidity) = router.addLiquidity(
            address(ikigaiToken),
            address(BERA),
            ikigaiAmount,
            beraAmount,
            ikigaiAmount * (10000 - config.maxSlippage) / 10000,
            beraAmount * (10000 - config.maxSlippage) / 10000,
            address(this),
            block.timestamp
        );

        emit LiquidityAdded(amountIkigai, amountBera, liquidity);
        _createSnapshot();
    }

    function removeLiquidity(
        uint256 lpTokens
    ) external nonReentrant whenNotPaused onlyRole(MANAGER_ROLE) {
        require(lpTokens > 0, "Invalid amount");
        
        uint256 currentLiquidity = pair.balanceOf(address(this));
        require(
            currentLiquidity - lpTokens >= config.minLiquidity,
            "Below min liquidity"
        );

        pair.approve(address(router), lpTokens);

        (uint256 amountIkigai, uint256 amountBera) = router.removeLiquidity(
            address(ikigaiToken),
            address(BERA),
            lpTokens,
            0,
            0,
            address(this),
            block.timestamp
        );

        emit LiquidityRemoved(amountIkigai, amountBera, lpTokens);
        _createSnapshot();
    }

    // Rebalancing functions
    function checkAndRebalance() external nonReentrant whenNotPaused onlyRole(REBALANCER_ROLE) {
        require(
            block.timestamp >= lastRebalanceTime + config.rebalanceInterval,
            "Too soon to rebalance"
        );

        (uint256 ikigaiReserve, uint256 beraReserve,) = pair.getReserves();
        uint256 currentRatio = (ikigaiReserve * 10000) / beraReserve;
        
        if (Math.abs(int256(currentRatio - config.targetRatio)) > config.rebalanceThreshold) {
            _rebalanceLiquidity(currentRatio > config.targetRatio);
            lastRebalanceTime = block.timestamp;
            emit RebalanceExecuted(block.timestamp, "Ratio deviation");
        }
    }

    function _rebalanceLiquidity(bool excessIkigai) internal {
        uint256 lpBalance = pair.balanceOf(address(this));
        uint256 adjustmentAmount = lpBalance * config.rebalanceThreshold / 10000;
        
        if (excessIkigai) {
            // Remove liquidity and sell IKIGAI
            _removeLiquidityAndSell(adjustmentAmount);
        } else {
            // Remove liquidity and buy IKIGAI
            _removeLiquidityAndBuy(adjustmentAmount);
        }
        
        _createSnapshot();
    }

    // Internal helper functions
    function _createSnapshot() internal {
        lastSnapshotId++;
        (uint256 ikigaiReserve, uint256 beraReserve,) = pair.getReserves();
        
        snapshots[lastSnapshotId] = LiquiditySnapshot({
            timestamp: block.timestamp,
            totalLiquidity: pair.totalSupply(),
            ikigaiReserve: ikigaiReserve,
            beraReserve: beraReserve,
            lpTokens: pair.balanceOf(address(this)),
            price: (beraReserve * 1e18) / ikigaiReserve
        });

        emit SnapshotCreated(lastSnapshotId, block.timestamp);
    }

    function _removeLiquidityAndSell(uint256 lpAmount) internal {
        // Implementation for removing liquidity and selling IKIGAI
    }

    function _removeLiquidityAndBuy(uint256 lpAmount) internal {
        // Implementation for removing liquidity and buying IKIGAI
    }

    // View functions
    function getLiquidityInfo() external view returns (
        uint256 totalLiquidity,
        uint256 protocolLiquidity,
        uint256 currentRatio,
        bool needsRebalance
    ) {
        (uint256 ikigaiReserve, uint256 beraReserve,) = pair.getReserves();
        totalLiquidity = pair.totalSupply();
        protocolLiquidity = pair.balanceOf(address(this));
        currentRatio = (ikigaiReserve * 10000) / beraReserve;
        needsRebalance = Math.abs(int256(currentRatio - config.targetRatio)) > config.rebalanceThreshold;
    }

    function getSnapshot(
        uint256 snapshotId
    ) external view returns (LiquiditySnapshot memory) {
        return snapshots[snapshotId];
    }
} 