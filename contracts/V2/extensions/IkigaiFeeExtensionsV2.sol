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
    bytes32 public constant COLLECTOR_ROLE = keccak256("COLLECTOR_ROLE");

    struct FeeConfig {
        uint256 tradingFee;        // Trading fee (basis points)
        uint256 stakingFee;        // Staking fee (basis points)
        uint256 withdrawalFee;     // Withdrawal fee (basis points)
        uint256 performanceFee;    // Performance fee (basis points)
        bool dynamicFees;          // Whether fees are dynamic
    }

    struct FeeDistribution {
        uint256 treasuryShare;     // Treasury allocation (basis points)
        uint256 stakingShare;      // Staking rewards allocation
        uint256 buybackShare;      // Token buyback allocation
        uint256 burnShare;         // Token burn allocation
        uint256 referralShare;     // Referral rewards allocation
    }

    struct FeeCollection {
        uint256 tradingFees;       // Collected trading fees
        uint256 stakingFees;       // Collected staking fees
        uint256 withdrawalFees;    // Collected withdrawal fees
        uint256 performanceFees;   // Collected performance fees
        uint256 lastDistribution;  // Last distribution timestamp
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    IIkigaiVaultV2 public vault;
    IIkigaiTreasuryV2 public treasury;
    
    mapping(address => FeeConfig) public feeConfigs;
    mapping(address => FeeDistribution) public feeDistributions;
    mapping(address => FeeCollection) public feeCollections;
    mapping(address => bool) public feeExempt;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_FEE = 1000; // 10%
    uint256 public constant DISTRIBUTION_INTERVAL = 1 days;
    
    // Events
    event FeeConfigUpdated(address indexed token, string feeType);
    event FeesCollected(address indexed token, uint256 amount);
    event FeesDistributed(address indexed token, uint256 amount);
    event FeeExemptionUpdated(address indexed account, bool status);

    constructor(
        address _ikigaiToken,
        address _vault,
        address _treasury
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        vault = IIkigaiVaultV2(_vault);
        treasury = IIkigaiTreasuryV2(_treasury);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Fee configuration
    function configureFees(
        address token,
        FeeConfig calldata config,
        FeeDistribution calldata distribution
    ) external onlyRole(FEE_MANAGER) {
        require(
            config.tradingFee <= MAX_FEE &&
            config.stakingFee <= MAX_FEE &&
            config.withdrawalFee <= MAX_FEE &&
            config.performanceFee <= MAX_FEE,
            "Fee too high"
        );
        
        require(
            distribution.treasuryShare +
            distribution.stakingShare +
            distribution.buybackShare +
            distribution.burnShare +
            distribution.referralShare == BASIS_POINTS,
            "Invalid distribution"
        );
        
        feeConfigs[token] = config;
        feeDistributions[token] = distribution;
        
        emit FeeConfigUpdated(token, "ALL");
    }

    // Fee collection
    function collectFees(
        address token,
        uint256 amount,
        string calldata feeType
    ) external onlyRole(COLLECTOR_ROLE) {
        require(amount > 0, "Invalid amount");
        
        FeeCollection storage collection = feeCollections[token];
        
        // Update fee collection based on type
        if (keccak256(bytes(feeType)) == keccak256(bytes("TRADING"))) {
            collection.tradingFees += amount;
        } else if (keccak256(bytes(feeType)) == keccak256(bytes("STAKING"))) {
            collection.stakingFees += amount;
        } else if (keccak256(bytes(feeType)) == keccak256(bytes("WITHDRAWAL"))) {
            collection.withdrawalFees += amount;
        } else if (keccak256(bytes(feeType)) == keccak256(bytes("PERFORMANCE"))) {
            collection.performanceFees += amount;
        }
        
        // Transfer fees to this contract
        require(
            IERC20(token).transferFrom(msg.sender, address(this), amount),
            "Fee transfer failed"
        );
        
        emit FeesCollected(token, amount);
    }

    // Fee distribution
    function distributeFees(
        address token
    ) external nonReentrant {
        FeeCollection storage collection = feeCollections[token];
        require(
            block.timestamp >= collection.lastDistribution + DISTRIBUTION_INTERVAL,
            "Too soon"
        );
        
        uint256 totalFees = collection.tradingFees +
            collection.stakingFees +
            collection.withdrawalFees +
            collection.performanceFees;
            
        require(totalFees > 0, "No fees to distribute");
        
        FeeDistribution storage distribution = feeDistributions[token];
        
        // Distribute to treasury
        uint256 treasuryAmount = (totalFees * distribution.treasuryShare) / BASIS_POINTS;
        if (treasuryAmount > 0) {
            require(
                IERC20(token).transfer(address(treasury), treasuryAmount),
                "Treasury transfer failed"
            );
        }
        
        // Distribute to staking rewards
        uint256 stakingAmount = (totalFees * distribution.stakingShare) / BASIS_POINTS;
        if (stakingAmount > 0) {
            require(
                IERC20(token).transfer(address(vault), stakingAmount),
                "Staking transfer failed"
            );
        }
        
        // Handle buyback
        uint256 buybackAmount = (totalFees * distribution.buybackShare) / BASIS_POINTS;
        if (buybackAmount > 0) {
            _executeBuyback(token, buybackAmount);
        }
        
        // Handle burn
        uint256 burnAmount = (totalFees * distribution.burnShare) / BASIS_POINTS;
        if (burnAmount > 0) {
            _executeBurn(token, burnAmount);
        }
        
        // Reset collection
        collection.tradingFees = 0;
        collection.stakingFees = 0;
        collection.withdrawalFees = 0;
        collection.performanceFees = 0;
        collection.lastDistribution = block.timestamp;
        
        emit FeesDistributed(token, totalFees);
    }

    // Fee exemption management
    function setFeeExempt(
        address account,
        bool exempt
    ) external onlyRole(FEE_MANAGER) {
        feeExempt[account] = exempt;
        emit FeeExemptionUpdated(account, exempt);
    }

    // Internal functions
    function _executeBuyback(
        address token,
        uint256 amount
    ) internal {
        // Implementation needed
    }

    function _executeBurn(
        address token,
        uint256 amount
    ) internal {
        // Implementation needed
    }

    // View functions
    function getFeeConfig(
        address token
    ) external view returns (FeeConfig memory) {
        return feeConfigs[token];
    }

    function getFeeDistribution(
        address token
    ) external view returns (FeeDistribution memory) {
        return feeDistributions[token];
    }

    function getFeeCollection(
        address token
    ) external view returns (FeeCollection memory) {
        return feeCollections[token];
    }

    function isFeeExempt(
        address account
    ) external view returns (bool) {
        return feeExempt[account];
    }
} 