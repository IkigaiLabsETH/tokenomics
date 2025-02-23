// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract IkigaiSecurityV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    struct SecurityConfig {
        uint256 maxGasPrice;
        uint256 maxSlippage;
        uint256 maxTransactionSize;
        uint256 minTimeBetweenTxs;
        bool requiresWhitelist;
    }

    struct RiskParameters {
        uint256 priceImpactLimit;
        uint256 volumeThreshold;
        uint256 volatilityThreshold;
        uint256 liquidityThreshold;
    }

    struct EmergencyAction {
        address initiator;
        uint256 timestamp;
        string reason;
        bool resolved;
    }

    // State variables
    SecurityConfig public securityConfig;
    RiskParameters public riskParams;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;
    mapping(address => uint256) public lastActionTime;
    mapping(uint256 => EmergencyAction) public emergencyActions;
    uint256 public emergencyActionCount;

    // Events
    event SecurityConfigUpdated(string parameter, uint256 value);
    event RiskParametersUpdated(string parameter, uint256 value);
    event WhitelistUpdated(address indexed account, bool status);
    event BlacklistUpdated(address indexed account, bool status);
    event EmergencyActionTriggered(
        uint256 indexed actionId,
        address indexed initiator,
        string reason
    );
    event EmergencyActionResolved(uint256 indexed actionId);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize security config
        securityConfig = SecurityConfig({
            maxGasPrice: 500 gwei,
            maxSlippage: 300, // 3%
            maxTransactionSize: 1000 ether,
            minTimeBetweenTxs: 1 minutes,
            requiresWhitelist: false
        });
        
        // Initialize risk parameters
        riskParams = RiskParameters({
            priceImpactLimit: 500, // 5%
            volumeThreshold: 1000 ether,
            volatilityThreshold: 2000, // 20%
            liquidityThreshold: 100 ether
        });
    }

    // Security checks
    modifier checkSecurity(uint256 amount) {
        require(!blacklist[msg.sender], "Account blacklisted");
        require(
            !securityConfig.requiresWhitelist || whitelist[msg.sender],
            "Account not whitelisted"
        );
        require(tx.gasprice <= securityConfig.maxGasPrice, "Gas price too high");
        require(amount <= securityConfig.maxTransactionSize, "Transaction too large");
        require(
            block.timestamp >= lastActionTime[msg.sender] + securityConfig.minTimeBetweenTxs,
            "Action too frequent"
        );
        _;
        lastActionTime[msg.sender] = block.timestamp;
    }

    // Configuration functions
    function updateSecurityConfig(
        string memory parameter,
        uint256 value
    ) external onlyRole(GUARDIAN_ROLE) {
        if (keccak256(bytes(parameter)) == keccak256(bytes("maxGasPrice"))) {
            securityConfig.maxGasPrice = value;
        } else if (keccak256(bytes(parameter)) == keccak256(bytes("maxSlippage"))) {
            securityConfig.maxSlippage = value;
        } // ... etc

        emit SecurityConfigUpdated(parameter, value);
    }

    function updateRiskParameters(
        string memory parameter,
        uint256 value
    ) external onlyRole(GUARDIAN_ROLE) {
        if (keccak256(bytes(parameter)) == keccak256(bytes("priceImpactLimit"))) {
            riskParams.priceImpactLimit = value;
        } // ... etc

        emit RiskParametersUpdated(parameter, value);
    }

    // Whitelist/Blacklist management
    function updateWhitelist(
        address account,
        bool status
    ) external onlyRole(OPERATOR_ROLE) {
        whitelist[account] = status;
        emit WhitelistUpdated(account, status);
    }

    function updateBlacklist(
        address account,
        bool status
    ) external onlyRole(GUARDIAN_ROLE) {
        blacklist[account] = status;
        emit BlacklistUpdated(account, status);
    }

    // Emergency actions
    function triggerEmergencyAction(
        string memory reason
    ) external onlyRole(GUARDIAN_ROLE) returns (uint256) {
        emergencyActionCount++;
        
        emergencyActions[emergencyActionCount] = EmergencyAction({
            initiator: msg.sender,
            timestamp: block.timestamp,
            reason: reason,
            resolved: false
        });

        _pause();
        
        emit EmergencyActionTriggered(
            emergencyActionCount,
            msg.sender,
            reason
        );

        return emergencyActionCount;
    }

    function resolveEmergencyAction(
        uint256 actionId
    ) external onlyRole(GUARDIAN_ROLE) {
        require(actionId <= emergencyActionCount, "Invalid action ID");
        require(!emergencyActions[actionId].resolved, "Already resolved");

        emergencyActions[actionId].resolved = true;
        
        if (actionId == emergencyActionCount) {
            _unpause();
        }

        emit EmergencyActionResolved(actionId);
    }

    // View functions
    function checkTransactionSecurity(
        address account,
        uint256 amount
    ) external view returns (bool, string memory) {
        if (blacklist[account]) return (false, "Account blacklisted");
        if (securityConfig.requiresWhitelist && !whitelist[account]) {
            return (false, "Account not whitelisted");
        }
        if (amount > securityConfig.maxTransactionSize) {
            return (false, "Transaction too large");
        }
        return (true, "");
    }
} 