// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiLendingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant LENDING_MANAGER = keccak256("LENDING_MANAGER");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    struct LendingPool {
        uint256 totalSupplied;     // Total tokens supplied
        uint256 totalBorrowed;     // Total tokens borrowed
        uint256 utilizationRate;   // Current utilization
        uint256 interestRate;      // Current interest rate
        bool isActive;             // Pool active status
    }

    struct UserPosition {
        uint256 supplied;          // Amount supplied
        uint256 borrowed;          // Amount borrowed
        uint256 collateral;        // Collateral amount
        uint256 lastUpdate;        // Last update time
        bool isLiquidatable;       // Liquidation status
    }

    struct RiskParams {
        uint256 maxLTV;           // Maximum loan-to-value
        uint256 liquidationThreshold; // Liquidation threshold
        uint256 liquidationPenalty;   // Liquidation penalty
        uint256 borrowLimit;       // Maximum borrow amount
        uint256 minCollateral;     // Minimum collateral
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => LendingPool) public lendingPools;
    mapping(bytes32 => mapping(address => UserPosition)) public userPositions;
    mapping(bytes32 => RiskParams) public riskParams;
    mapping(address => bool) public whitelistedAssets;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_COLLATERAL_RATIO = 12000; // 120%
    uint256 public constant LIQUIDATION_BONUS = 500; // 5%
    
    // Events
    event PoolCreated(bytes32 indexed poolId, uint256 interestRate);
    event Supplied(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Borrowed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Liquidated(bytes32 indexed poolId, address indexed user, uint256 amount);

    constructor(
        address _vault,
        address _oracle
    ) {
        vault = IIkigaiVaultV2(_vault);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createPool(
        bytes32 poolId,
        uint256 interestRate,
        RiskParams calldata _riskParams
    ) external onlyRole(LENDING_MANAGER) {
        require(!lendingPools[poolId].isActive, "Pool exists");
        require(interestRate > 0, "Invalid rate");
        
        lendingPools[poolId] = LendingPool({
            totalSupplied: 0,
            totalBorrowed: 0,
            utilizationRate: 0,
            interestRate: interestRate,
            isActive: true
        });
        
        riskParams[poolId] = _riskParams;
        
        emit PoolCreated(poolId, interestRate);
    }

    // Supply operations
    function supply(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        
        LendingPool storage pool = lendingPools[poolId];
        UserPosition storage position = userPositions[poolId][msg.sender];
        
        require(pool.isActive, "Pool not active");
        
        // Transfer tokens
        IERC20(vault.token()).transferFrom(msg.sender, address(this), amount);
        
        // Update position
        position.supplied += amount;
        position.lastUpdate = block.timestamp;
        
        // Update pool
        pool.totalSupplied += amount;
        pool.utilizationRate = _calculateUtilization(poolId);
        
        emit Supplied(poolId, msg.sender, amount);
    }

    // Borrow operations
    function borrow(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(amount > 0, "Invalid amount");
        
        LendingPool storage pool = lendingPools[poolId];
        UserPosition storage position = userPositions[poolId][msg.sender];
        RiskParams storage params = riskParams[poolId];
        
        require(pool.isActive, "Pool not active");
        require(amount <= _calculateBorrowLimit(poolId, msg.sender), "Exceeds limit");
        
        // Update position
        position.borrowed += amount;
        position.lastUpdate = block.timestamp;
        
        // Check health
        require(
            _checkPositionHealth(poolId, msg.sender),
            "Unhealthy position"
        );
        
        // Update pool
        pool.totalBorrowed += amount;
        pool.utilizationRate = _calculateUtilization(poolId);
        
        // Transfer tokens
        IERC20(vault.token()).transfer(msg.sender, amount);
        
        emit Borrowed(poolId, msg.sender, amount);
    }

    // Liquidation
    function liquidate(
        bytes32 poolId,
        address user
    ) external onlyRole(LIQUIDATOR_ROLE) nonReentrant {
        UserPosition storage position = userPositions[poolId][user];
        require(position.isLiquidatable, "Not liquidatable");
        
        uint256 collateralValue = _getCollateralValue(poolId, user);
        uint256 debtValue = _getDebtValue(poolId, user);
        
        require(collateralValue < debtValue, "Position healthy");
        
        // Calculate liquidation amount
        uint256 liquidationAmount = _calculateLiquidationAmount(
            poolId,
            collateralValue,
            debtValue
        );
        
        // Execute liquidation
        _executeLiquidation(poolId, user, liquidationAmount);
        
        emit Liquidated(poolId, user, liquidationAmount);
    }

    // Internal functions
    function _calculateUtilization(
        bytes32 poolId
    ) internal view returns (uint256) {
        LendingPool storage pool = lendingPools[poolId];
        if (pool.totalSupplied == 0) return 0;
        return (pool.totalBorrowed * BASIS_POINTS) / pool.totalSupplied;
    }

    function _calculateBorrowLimit(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _checkPositionHealth(
        bytes32 poolId,
        address user
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    function _getCollateralValue(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getDebtValue(
        bytes32 poolId,
        address user
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateLiquidationAmount(
        bytes32 poolId,
        uint256 collateralValue,
        uint256 debtValue
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _executeLiquidation(
        bytes32 poolId,
        address user,
        uint256 amount
    ) internal {
        // Implementation needed
    }

    // View functions
    function getLendingPool(
        bytes32 poolId
    ) external view returns (LendingPool memory) {
        return lendingPools[poolId];
    }

    function getUserPosition(
        bytes32 poolId,
        address user
    ) external view returns (UserPosition memory) {
        return userPositions[poolId][user];
    }

    function getRiskParams(
        bytes32 poolId
    ) external view returns (RiskParams memory) {
        return riskParams[poolId];
    }

    function isAssetWhitelisted(
        address asset
    ) external view returns (bool) {
        return whitelistedAssets[asset];
    }
} 