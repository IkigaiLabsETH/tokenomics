// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiFeeExtensionsV2.sol";

contract IkigaiTreasuryExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TREASURY_MANAGER = keccak256("TREASURY_MANAGER");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    struct TreasuryConfig {
        uint256 minReserve;      // Minimum reserve
        uint256 maxAllocation;   // Maximum allocation
        uint256 rebalanceThreshold; // Rebalance threshold
        uint256 cooldownPeriod;  // Action cooldown
        bool requiresVote;       // Vote requirement
    }

    struct AssetAllocation {
        uint256 targetWeight;    // Target allocation
        uint256 currentWeight;   // Current allocation
        uint256 minWeight;       // Minimum weight
        uint256 maxWeight;       // Maximum weight
        bool isActive;           // Asset status
    }

    struct TreasuryStats {
        uint256 totalValue;      // Total value
        uint256 totalReserves;   // Total reserves
        uint256 totalAllocated;  // Total allocated
        uint256 lastRebalance;   // Last rebalance
        uint256 lastReport;      // Last report time
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiFeeExtensionsV2 public feeExtension;
    IERC20 public treasuryToken;
    
    mapping(bytes32 => TreasuryConfig) public treasuryConfigs;
    mapping(address => AssetAllocation) public assetAllocations;
    mapping(bytes32 => TreasuryStats) public treasuryStats;
    mapping(address => bool) public approvedAssets;
    
    uint256 public constant MAX_ALLOCATION = 8000; // 80%
    uint256 public constant MIN_RESERVE = 1000e18;
    uint256 public constant REBALANCE_INTERVAL = 1 days;
    
    // Events
    event TreasuryConfigUpdated(bytes32 indexed configId);
    event AllocationUpdated(address indexed asset, uint256 weight);
    event RebalanceExecuted(bytes32 indexed configId, uint256 timestamp);
    event AssetApproved(address indexed asset, bool status);

    constructor(
        address _vault,
        address _feeExtension,
        address _treasuryToken
    ) {
        vault = IIkigaiVaultV2(_vault);
        feeExtension = IIkigaiFeeExtensionsV2(_feeExtension);
        treasuryToken = IERC20(_treasuryToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Treasury configuration
    function updateTreasuryConfig(
        bytes32 configId,
        TreasuryConfig calldata config
    ) external onlyRole(TREASURY_MANAGER) {
        require(config.maxAllocation <= MAX_ALLOCATION, "Allocation too high");
        require(config.minReserve >= MIN_RESERVE, "Reserve too low");
        
        treasuryConfigs[configId] = config;
        
        emit TreasuryConfigUpdated(configId);
    }

    // Asset allocation
    function updateAllocation(
        address asset,
        uint256 targetWeight,
        uint256 minWeight,
        uint256 maxWeight
    ) external onlyRole(ALLOCATOR_ROLE) {
        require(approvedAssets[asset], "Asset not approved");
        require(targetWeight <= maxWeight, "Invalid target");
        require(minWeight <= targetWeight, "Invalid min");
        
        AssetAllocation storage allocation = assetAllocations[asset];
        allocation.targetWeight = targetWeight;
        allocation.minWeight = minWeight;
        allocation.maxWeight = maxWeight;
        allocation.isActive = true;
        
        // Check if rebalance needed
        _checkRebalance(asset);
        
        emit AllocationUpdated(asset, targetWeight);
    }

    // Rebalancing
    function executeRebalance(
        bytes32 configId
    ) external onlyRole(ALLOCATOR_ROLE) nonReentrant {
        TreasuryConfig storage config = treasuryConfigs[configId];
        TreasuryStats storage stats = treasuryStats[configId];
        
        require(
            block.timestamp >= stats.lastRebalance + REBALANCE_INTERVAL,
            "Too soon"
        );
        
        // Check reserves
        require(
            _getCurrentReserves() >= config.minReserve,
            "Insufficient reserves"
        );
        
        // Perform rebalancing
        _executeRebalance(configId);
        
        // Update stats
        stats.lastRebalance = block.timestamp;
        stats.totalValue = _calculateTotalValue();
        stats.totalAllocated = _calculateTotalAllocated();
        stats.totalReserves = _getCurrentReserves();
        
        emit RebalanceExecuted(configId, block.timestamp);
    }

    // Asset management
    function approveAsset(
        address asset,
        bool status
    ) external onlyRole(TREASURY_MANAGER) {
        approvedAssets[asset] = status;
        emit AssetApproved(asset, status);
    }

    // Internal functions
    function _checkRebalance(
        address asset
    ) internal view {
        AssetAllocation storage allocation = assetAllocations[asset];
        uint256 currentWeight = _getCurrentWeight(asset);
        
        if (currentWeight < allocation.minWeight || currentWeight > allocation.maxWeight) {
            // Trigger rebalance
            _rebalanceAsset(asset);
        }
    }

    function _executeRebalance(
        bytes32 configId
    ) internal {
        // Implementation needed
    }

    function _rebalanceAsset(
        address asset
    ) internal {
        // Implementation needed
    }

    function _getCurrentReserves() internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateTotalValue() internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _calculateTotalAllocated() internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getCurrentWeight(
        address asset
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    // View functions
    function getTreasuryConfig(
        bytes32 configId
    ) external view returns (TreasuryConfig memory) {
        return treasuryConfigs[configId];
    }

    function getAssetAllocation(
        address asset
    ) external view returns (AssetAllocation memory) {
        return assetAllocations[asset];
    }

    function getTreasuryStats(
        bytes32 configId
    ) external view returns (TreasuryStats memory) {
        return treasuryStats[configId];
    }

    function isAssetApproved(
        address asset
    ) external view returns (bool) {
        return approvedAssets[asset];
    }
} 