// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiSecurityExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant SECURITY_MANAGER = keccak256("SECURITY_MANAGER");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    struct SecurityConfig {
        uint256 maxGasPrice;     // Maximum gas price
        uint256 maxTxValue;      // Maximum transaction value
        uint256 cooldownPeriod;  // Action cooldown
        uint256 rateLimit;       // Rate limiting
        bool requiresGuardian;   // Guardian requirement
    }

    struct GuardianAction {
        bytes32 actionType;      // Action type
        address target;          // Target address
        uint256 value;          // Action value
        uint256 timestamp;      // Action time
        bool approved;          // Approval status
    }

    struct RiskParams {
        uint256 maxExposure;     // Maximum exposure
        uint256 minCollateral;   // Minimum collateral
        uint256 liquidationThreshold; // Liquidation threshold
        uint256 penaltyRate;    // Penalty rate
        bool active;            // Risk status
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => SecurityConfig) public securityConfigs;
    mapping(bytes32 => GuardianAction[]) public guardianActions;
    mapping(address => RiskParams) public riskParams;
    mapping(address => bool) public blacklistedAddresses;
    
    uint256 public constant MAX_GAS_PRICE = 1000 gwei;
    uint256 public constant MIN_COOLDOWN = 1 hours;
    uint256 public constant MAX_RATE_LIMIT = 1000;
    
    // Events
    event SecurityConfigUpdated(bytes32 indexed configId);
    event GuardianActionExecuted(bytes32 indexed actionId);
    event RiskParamsUpdated(address indexed target);
    event AddressBlacklisted(address indexed target, bool status);

    constructor(
        address _vault,
        address _oracle
    ) {
        vault = IIkigaiVaultV2(_vault);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Security configuration
    function updateSecurityConfig(
        bytes32 configId,
        SecurityConfig calldata config
    ) external onlyRole(SECURITY_MANAGER) {
        require(config.maxGasPrice <= MAX_GAS_PRICE, "Gas price too high");
        require(config.cooldownPeriod >= MIN_COOLDOWN, "Cooldown too short");
        require(config.rateLimit <= MAX_RATE_LIMIT, "Rate limit too high");
        
        securityConfigs[configId] = config;
        
        emit SecurityConfigUpdated(configId);
    }

    // Guardian actions
    function executeGuardianAction(
        bytes32 actionId,
        bytes32 actionType,
        address target,
        uint256 value
    ) external onlyRole(GUARDIAN_ROLE) nonReentrant {
        require(!blacklistedAddresses[target], "Target blacklisted");
        
        SecurityConfig storage config = securityConfigs[actionType];
        require(config.requiresGuardian, "Guardian not required");
        
        // Validate action
        require(
            _validateGuardianAction(actionType, target, value),
            "Invalid action"
        );
        
        // Record action
        guardianActions[actionId].push(GuardianAction({
            actionType: actionType,
            target: target,
            value: value,
            timestamp: block.timestamp,
            approved: true
        }));
        
        // Execute action
        _executeAction(actionType, target, value);
        
        emit GuardianActionExecuted(actionId);
    }

    // Risk management
    function updateRiskParams(
        address target,
        RiskParams calldata params
    ) external onlyRole(SECURITY_MANAGER) {
        require(params.maxExposure > 0, "Invalid exposure");
        require(params.minCollateral > 0, "Invalid collateral");
        require(params.liquidationThreshold > 0, "Invalid threshold");
        
        riskParams[target] = params;
        
        emit RiskParamsUpdated(target);
    }

    // Blacklist management
    function updateBlacklist(
        address target,
        bool status
    ) external onlyRole(SECURITY_MANAGER) {
        blacklistedAddresses[target] = status;
        
        emit AddressBlacklisted(target, status);
    }

    // Internal functions
    function _validateGuardianAction(
        bytes32 actionType,
        address target,
        uint256 value
    ) internal view returns (bool) {
        SecurityConfig storage config = securityConfigs[actionType];
        
        // Check value limit
        if (value > config.maxTxValue) {
            return false;
        }
        
        // Check rate limit
        if (!_checkRateLimit(actionType)) {
            return false;
        }
        
        // Check cooldown
        if (!_checkCooldown(actionType)) {
            return false;
        }
        
        return true;
    }

    function _executeAction(
        bytes32 actionType,
        address target,
        uint256 value
    ) internal {
        // Implementation needed
    }

    function _checkRateLimit(
        bytes32 actionType
    ) internal view returns (bool) {
        // Implementation needed
        return true;
    }

    function _checkCooldown(
        bytes32 actionType
    ) internal view returns (bool) {
        // Implementation needed
        return true;
    }

    // View functions
    function getSecurityConfig(
        bytes32 configId
    ) external view returns (SecurityConfig memory) {
        return securityConfigs[configId];
    }

    function getGuardianActions(
        bytes32 actionId
    ) external view returns (GuardianAction[] memory) {
        return guardianActions[actionId];
    }

    function getRiskParams(
        address target
    ) external view returns (RiskParams memory) {
        return riskParams[target];
    }

    function isBlacklisted(
        address target
    ) external view returns (bool) {
        return blacklistedAddresses[target];
    }
} 