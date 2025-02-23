// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiTreasuryV2.sol";

contract IkigaiFeeExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant FEE_MANAGER = keccak256("FEE_MANAGER");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    struct FeeConfig {
        uint256 tradingFee;      // Trading fee (basis points)
        uint256 protocolFee;     // Protocol fee (basis points)
        uint256 stakingFee;      // Staking reward fee (basis points)
        uint256 treasuryFee;     // Treasury fee (basis points)
        bool isActive;           // Fee config status
    }

    struct FeeDistribution {
        uint256 protocolShare;   // Protocol share percentage
        uint256 stakingShare;    // Staking share percentage
        uint256 treasuryShare;   // Treasury share percentage
        uint256 burnShare;       // Burn share percentage
        bool isActive;           // Distribution status
    }

    struct FeeStats {
        uint256 totalCollected;  // Total fees collected
        uint256 totalDistributed; // Total fees distributed
        uint256 lastDistribution; // Last distribution time
        uint256 periodRevenue;   // Current period revenue
        uint256 periodStart;     // Current period start
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiTreasuryV2 public treasury;
    IERC20 public feeToken;
    
    mapping(bytes32 => FeeConfig) public feeConfigs;
    mapping(bytes32 => FeeDistribution) public distributions;
    mapping(address => FeeStats) public feeStats;
    mapping(address => bool) public feeExempt;
    
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public constant DISTRIBUTION_PERIOD = 1 days;
    uint256 public constant MIN_DISTRIBUTION = 100e18;
    
    // Events
    event FeeConfigUpdated(bytes32 indexed configId);
    event FeesCollected(address indexed token, uint256 amount);
    event FeesDistributed(bytes32 indexed configId, uint256 amount);
    event FeeExemptionUpdated(address indexed account, bool status);

    constructor(
        address _vault,
        address _treasury,
        address _feeToken
    ) {
        vault = IIkigaiVaultV2(_vault);
        treasury = IIkigaiTreasuryV2(_treasury);
        feeToken = IERC20(_feeToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Fee configuration
    function updateFeeConfig(
        bytes32 configId,
        FeeConfig calldata config
    ) external onlyRole(FEE_MANAGER) {
        require(
            config.tradingFee + config.protocolFee + config.stakingFee + config.treasuryFee <= MAX_FEE,
            "Total fee too high"
        );
        
        feeConfigs[configId] = config;
        
        emit FeeConfigUpdated(configId);
    }

    // Fee collection
    function collectFees(
        bytes32 configId,
        address token,
        uint256 amount
    ) external nonReentrant whenNotPaused {
        require(!feeExempt[msg.sender], "Fee exempt");
        
        FeeConfig storage config = feeConfigs[configId];
        require(config.isActive, "Config not active");
        
        // Transfer fees
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        // Update stats
        FeeStats storage stats = feeStats[token];
        stats.totalCollected += amount;
        stats.periodRevenue += amount;
        
        if (stats.periodStart == 0) {
            stats.periodStart = block.timestamp;
        }
        
        emit FeesCollected(token, amount);
    }

    // Fee distribution
    function distributeFees(
        bytes32 configId
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant {
        FeeConfig storage config = feeConfigs[configId];
        FeeDistribution storage dist = distributions[configId];
        require(config.isActive && dist.isActive, "Not active");
        
        FeeStats storage stats = feeStats[address(feeToken)];
        require(
            block.timestamp >= stats.lastDistribution + DISTRIBUTION_PERIOD,
            "Too soon"
        );
        require(stats.periodRevenue >= MIN_DISTRIBUTION, "Below minimum");
        
        uint256 amount = stats.periodRevenue;
        
        // Distribute to protocol
        if (dist.protocolShare > 0) {
            uint256 protocolAmount = (amount * dist.protocolShare) / 10000;
            _distributeToProtocol(protocolAmount);
        }
        
        // Distribute to staking
        if (dist.stakingShare > 0) {
            uint256 stakingAmount = (amount * dist.stakingShare) / 10000;
            _distributeToStaking(stakingAmount);
        }
        
        // Distribute to treasury
        if (dist.treasuryShare > 0) {
            uint256 treasuryAmount = (amount * dist.treasuryShare) / 10000;
            _distributeToTreasury(treasuryAmount);
        }
        
        // Handle burns
        if (dist.burnShare > 0) {
            uint256 burnAmount = (amount * dist.burnShare) / 10000;
            _handleBurn(burnAmount);
        }
        
        // Update stats
        stats.totalDistributed += amount;
        stats.periodRevenue = 0;
        stats.lastDistribution = block.timestamp;
        stats.periodStart = block.timestamp;
        
        emit FeesDistributed(configId, amount);
    }

    // Internal functions
    function _distributeToProtocol(
        uint256 amount
    ) internal {
        // Implementation needed
    }

    function _distributeToStaking(
        uint256 amount
    ) internal {
        // Implementation needed
    }

    function _distributeToTreasury(
        uint256 amount
    ) internal {
        // Implementation needed
    }

    function _handleBurn(
        uint256 amount
    ) internal {
        // Implementation needed
    }

    function _validateFeeAmount(
        uint256 amount
    ) internal pure returns (bool) {
        // Implementation needed
        return true;
    }

    // View functions
    function getFeeConfig(
        bytes32 configId
    ) external view returns (FeeConfig memory) {
        return feeConfigs[configId];
    }

    function getDistribution(
        bytes32 configId
    ) external view returns (FeeDistribution memory) {
        return distributions[configId];
    }

    function getFeeStats(
        address token
    ) external view returns (FeeStats memory) {
        return feeStats[token];
    }

    function isFeeExempt(
        address account
    ) external view returns (bool) {
        return feeExempt[account];
    }
} 