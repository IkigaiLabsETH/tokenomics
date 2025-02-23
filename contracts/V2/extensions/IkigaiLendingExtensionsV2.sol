// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiOracleV2.sol";
import "../interfaces/IIkigaiVaultV2.sol";

contract IkigaiLendingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant LENDING_MANAGER = keccak256("LENDING_MANAGER");
    bytes32 public constant LIQUIDATOR_ROLE = keccak256("LIQUIDATOR_ROLE");

    struct LendingPool {
        address asset;           // Lending asset
        uint256 totalSupply;    // Total supplied
        uint256 totalBorrowed;  // Total borrowed
        uint256 utilizationRate; // Current utilization
        uint256 interestRate;   // Current interest rate
        bool isActive;          // Pool status
    }

    struct UserLending {
        uint256 supplied;       // Amount supplied
        uint256 borrowed;       // Amount borrowed
        uint256 collateral;     // Collateral value
        uint256 lastUpdate;     // Last update time
        bool isLiquidatable;    // Liquidation status
    }

    struct LendingConfig {
        uint256 maxLTV;         // Maximum loan-to-value
        uint256 liquidationThreshold; // Liquidation threshold
        uint256 borrowCap;      // Maximum borrow amount
        uint256 reserveFactor;  // Reserve factor
        bool requiresCollateral; // Collateral requirement
    }

    // State variables
    IIkigaiOracleV2 public oracle;
    IIkigaiVaultV2 public vault;
    
    mapping(bytes32 => LendingPool) public lendingPools;
    mapping(bytes32 => mapping(address => UserLending)) public userLendings;
    mapping(bytes32 => LendingConfig) public lendingConfigs;
    mapping(address => bool) public supportedAssets;
    
    uint256 public constant MAX_LTV = 8000; // 80%
    uint256 public constant MIN_COLLATERAL = 1000e18;
    uint256 public constant INTEREST_RATE_BASE = 1000; // 10%
    
    // Events
    event PoolCreated(bytes32 indexed poolId, address asset);
    event Supplied(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Borrowed(bytes32 indexed poolId, address indexed user, uint256 amount);
    event Liquidated(bytes32 indexed poolId, address indexed user, uint256 amount);

    constructor(
        address _oracle,
        address _vault
    ) {
        oracle = IIkigaiOracleV2(_oracle);
        vault = IIkigaiVaultV2(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Pool management
    function createLendingPool(
        bytes32 poolId,
        address asset,
        LendingConfig calldata config
    ) external onlyRole(LENDING_MANAGER) {
        require(!lendingPools[poolId].isActive, "Pool exists");
        require(supportedAssets[asset], "Asset not supported");
        require(config.maxLTV <= MAX_LTV, "LTV too high");
        
        lendingPools[poolId] = LendingPool({
            asset: asset,
            totalSupply: 0,
            totalBorrowed: 0,
            utilizationRate: 0,
            interestRate: INTEREST_RATE_BASE,
            isActive: true
        });
        
        lendingConfigs[poolId] = config;
        
        emit PoolCreated(poolId, asset);
    }

    // Supply functions
    function supply(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        LendingPool storage pool = lendingPools[poolId];
        require(pool.isActive, "Pool not active");
        
        // Update interest
        _updateInterest(poolId);
        
        // Transfer tokens
        IERC20(pool.asset).transferFrom(msg.sender, address(this), amount);
        
        // Update state
        UserLending storage lending = userLendings[poolId][msg.sender];
        lending.supplied += amount;
        lending.lastUpdate = block.timestamp;
        
        pool.totalSupply += amount;
        
        // Update rates
        _updatePoolRates(poolId);
        
        emit Supplied(poolId, msg.sender, amount);
    }

    // Borrow functions
    function borrow(
        bytes32 poolId,
        uint256 amount
    ) external nonReentrant {
        LendingPool storage pool = lendingPools[poolId];
        LendingConfig storage config = lendingConfigs[poolId];
        require(pool.isActive, "Pool not active");
        
        UserLending storage lending = userLendings[poolId][msg.sender];
        require(
            lending.collateral >= _calculateRequiredCollateral(poolId, amount),
            "Insufficient collateral"
        );
        
        // Check borrow cap
        require(
            pool.totalBorrowed + amount <= config.borrowCap,
            "Exceeds borrow cap"
        );
        
        // Update interest
        _updateInterest(poolId);
        
        // Transfer tokens
        IERC20(pool.asset).transfer(msg.sender, amount);
        
        // Update state
        lending.borrowed += amount;
        lending.lastUpdate = block.timestamp;
        
        pool.totalBorrowed += amount;
        
        // Update rates
        _updatePoolRates(poolId);
        
        emit Borrowed(poolId, msg.sender, amount);
    }

    // Liquidation functions
    function liquidate(
        bytes32 poolId,
        address user
    ) external onlyRole(LIQUIDATOR_ROLE) nonReentrant {
        UserLending storage lending = userLendings[poolId][msg.sender];
        require(lending.isLiquidatable, "Not liquidatable");
        
        LendingPool storage pool = lendingPools[poolId];
        LendingConfig storage config = lendingConfigs[poolId];
        
        // Calculate liquidation amount
        uint256 liquidationAmount = _calculateLiquidationAmount(poolId, user);
        
        // Handle liquidation
        _executeLiquidation(poolId, user, liquidationAmount);
        
        emit Liquidated(poolId, user, liquidationAmount);
    }

    // Internal functions
    function _updateInterest(
        bytes32 poolId
    ) internal {
        LendingPool storage pool = lendingPools[poolId];
        
        uint256 interest = _calculateInterest(poolId);
        pool.totalBorrowed += interest;
    }

    function _updatePoolRates(
        bytes32 poolId
    ) internal {
        LendingPool storage pool = lendingPools[poolId];
        
        if (pool.totalSupply > 0) {
            pool.utilizationRate = (pool.totalBorrowed * 10000) / pool.totalSupply;
            pool.interestRate = _calculateInterestRate(pool.utilizationRate);
        }
    }

    function _calculateRequiredCollateral(
        bytes32 poolId,
        uint256 amount
    ) internal view returns (uint256) {
        LendingConfig storage config = lendingConfigs[poolId];
        return (amount * 10000) / config.maxLTV;
    }

    function _calculateLiquidationAmount(
        bytes32 poolId,
        address user
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

    function _calculateInterest(
        bytes32 poolId
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateInterestRate(
        uint256 utilization
    ) internal pure returns (uint256) {
        // Base rate + utilization factor
        return INTEREST_RATE_BASE + (utilization / 100);
    }

    // View functions
    function getLendingPool(
        bytes32 poolId
    ) external view returns (LendingPool memory) {
        return lendingPools[poolId];
    }

    function getUserLending(
        bytes32 poolId,
        address user
    ) external view returns (UserLending memory) {
        return userLendings[poolId][user];
    }

    function getLendingConfig(
        bytes32 poolId
    ) external view returns (LendingConfig memory) {
        return lendingConfigs[poolId];
    }

    function isAssetSupported(
        address asset
    ) external view returns (bool) {
        return supportedAssets[asset];
    }
} 