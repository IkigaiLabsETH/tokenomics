// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiMonitoringExtensionsV2.sol";

contract IkigaiSecurityExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant SECURITY_MANAGER = keccak256("SECURITY_MANAGER");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    struct SecurityConfig {
        uint256 maxGasPrice;       // Maximum gas price
        uint256 maxTxValue;        // Maximum transaction value
        uint256 cooldownPeriod;    // Action cooldown period
        uint256 timelock;          // Timelock duration
        bool requiresApproval;     // Whether approval required
    }

    struct RiskLimit {
        uint256 dailyLimit;        // Daily transaction limit
        uint256 txLimit;           // Per-transaction limit
        uint256 userLimit;         // Per-user limit
        uint256 contractLimit;     // Per-contract limit
        bool isActive;             // Limit active status
    }

    struct SecurityStats {
        uint256 blockedTx;         // Number of blocked transactions
        uint256 riskLevel;         // Current risk level
        uint256 lastIncident;      // Last incident timestamp
        uint256 totalIncidents;    // Total security incidents
        bool emergencyMode;        // Emergency mode status
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiMonitoringExtensionsV2 public monitoring;
    
    mapping(address => SecurityConfig) public securityConfigs;
    mapping(address => RiskLimit) public riskLimits;
    mapping(address => SecurityStats) public securityStats;
    mapping(address => bool) public blacklistedAddresses;
    
    uint256 public constant MAX_RISK_LEVEL = 100;
    uint256 public constant MIN_TIMELOCK = 1 hours;
    uint256 public constant EMERGENCY_TIMEOUT = 24 hours;
    
    // Events
    event SecurityConfigured(address indexed target, uint256 timelock);
    event RiskLimitUpdated(address indexed target, uint256 limit);
    event SecurityIncident(address indexed target, string details);
    event EmergencyAction(address indexed target, string action);

    constructor(
        address _vault,
        address _monitoring
    ) {
        vault = IIkigaiVaultV2(_vault);
        monitoring = IIkigaiMonitoringExtensionsV2(_monitoring);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Security configuration
    function configureSecurity(
        address target,
        SecurityConfig calldata config,
        RiskLimit calldata limits
    ) external onlyRole(SECURITY_MANAGER) {
        require(config.timelock >= MIN_TIMELOCK, "Timelock too short");
        require(limits.dailyLimit >= limits.txLimit, "Invalid limits");
        
        securityConfigs[target] = config;
        riskLimits[target] = limits;
        
        emit SecurityConfigured(target, config.timelock);
        emit RiskLimitUpdated(target, limits.dailyLimit);
    }

    // Transaction validation
    function validateTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external view returns (bool isValid, string memory reason) {
        SecurityConfig storage config = securityConfigs[target];
        RiskLimit storage limits = riskLimits[target];
        
        // Check blacklist
        if (blacklistedAddresses[target]) {
            return (false, "Address blacklisted");
        }
        
        // Check gas price
        if (tx.gasprice > config.maxGasPrice) {
            return (false, "Gas price too high");
        }
        
        // Check value limits
        if (value > limits.txLimit) {
            return (false, "Value exceeds limit");
        }
        
        // Check risk level
        if (_calculateRiskLevel(target, value, data) > MAX_RISK_LEVEL) {
            return (false, "Risk too high");
        }
        
        return (true, "");
    }

    // Emergency controls
    function triggerEmergency(
        address target,
        string calldata reason
    ) external onlyRole(GUARDIAN_ROLE) {
        SecurityStats storage stats = securityStats[target];
        require(!stats.emergencyMode, "Already in emergency");
        
        // Activate emergency mode
        stats.emergencyMode = true;
        stats.lastIncident = block.timestamp;
        stats.totalIncidents++;
        
        // Notify monitoring
        monitoring.handleAlert(
            keccak256("SECURITY_EMERGENCY"),
            reason
        );
        
        emit EmergencyAction(target, "EMERGENCY_ACTIVATED");
    }

    // Risk management
    function updateRiskLimits(
        address target,
        RiskLimit calldata newLimits
    ) external onlyRole(SECURITY_MANAGER) {
        require(newLimits.dailyLimit > 0, "Invalid daily limit");
        require(newLimits.txLimit <= newLimits.dailyLimit, "Invalid tx limit");
        
        riskLimits[target] = newLimits;
        
        emit RiskLimitUpdated(target, newLimits.dailyLimit);
    }

    // Blacklist management
    function updateBlacklist(
        address target,
        bool blacklisted
    ) external onlyRole(SECURITY_MANAGER) {
        blacklistedAddresses[target] = blacklisted;
        
        if (blacklisted) {
            SecurityStats storage stats = securityStats[target];
            stats.blockedTx++;
            stats.riskLevel = MAX_RISK_LEVEL;
        }
        
        emit SecurityIncident(target, blacklisted ? "BLACKLISTED" : "UNBLACKLISTED");
    }

    // Internal functions
    function _calculateRiskLevel(
        address target,
        uint256 value,
        bytes calldata data
    ) internal view returns (uint256) {
        // Implementation needed - calculate risk based on various factors
        return 0;
    }

    function _validateTimelock(
        address target,
        bytes32 actionHash
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    function _checkLimits(
        address target,
        uint256 value
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    function _updateSecurityStats(
        address target,
        bool isIncident
    ) internal {
        // Implementation needed
    }

    // View functions
    function getSecurityConfig(
        address target
    ) external view returns (SecurityConfig memory) {
        return securityConfigs[target];
    }

    function getRiskLimit(
        address target
    ) external view returns (RiskLimit memory) {
        return riskLimits[target];
    }

    function getSecurityStats(
        address target
    ) external view returns (SecurityStats memory) {
        return securityStats[target];
    }

    function isBlacklisted(
        address target
    ) external view returns (bool) {
        return blacklistedAddresses[target];
    }
} 