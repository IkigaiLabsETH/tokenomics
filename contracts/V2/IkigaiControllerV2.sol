// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract IkigaiControllerV2 is AccessControl, Pausable, ReentrancyGuard {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    struct ProtocolConfig {
        uint256 minTradeSize;      // Minimum trade size to prevent spam
        uint256 maxTradeSize;      // Maximum trade size for safety
        uint256 tradeCooldown;     // Cooldown between trades
        uint256 maxDailyVolume;    // Max volume per user per day
        bool requiresKYC;          // Whether KYC is required
        uint256 emergencyTimeout;  // Timeout for emergency actions
    }

    struct SecurityConfig {
        uint256 maxGasPrice;       // Maximum gas price for transactions
        uint256 maxSlippage;       // Maximum allowed slippage
        uint256 circuitBreaker;    // Price change % to trigger circuit breaker
        uint256 rateLimit;         // Maximum actions per time window
        uint256 timeWindow;        // Time window for rate limiting
    }

    ProtocolConfig public protocolConfig;
    SecurityConfig public securityConfig;
    
    mapping(address => bool) public kycApproved;
    mapping(address => uint256) public userDailyVolume;
    mapping(address => uint256) public lastTradeTimestamp;
    mapping(address => uint256) public actionCount;
    
    event ConfigUpdated(string configType, string parameter, uint256 value);
    event KYCStatusUpdated(address indexed user, bool status);
    event EmergencyActionTriggered(string action, address indexed trigger);
    event CircuitBreakerTriggered(string reason, uint256 timestamp);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        
        // Initialize default protocol config
        protocolConfig = ProtocolConfig({
            minTradeSize: 0.1 ether,    // 0.1 BERA minimum
            maxTradeSize: 1000 ether,   // 1000 BERA maximum
            tradeCooldown: 1 minutes,   // 1 minute between trades
            maxDailyVolume: 10000 ether, // 10,000 BERA daily limit
            requiresKYC: false,         // KYC not required initially
            emergencyTimeout: 24 hours  // 24 hour emergency timeout
        });
        
        // Initialize security config
        securityConfig = SecurityConfig({
            maxGasPrice: 500 gwei,     // Maximum gas price
            maxSlippage: 300,          // 3% max slippage
            circuitBreaker: 2000,      // 20% price change trigger
            rateLimit: 10,             // 10 actions per window
            timeWindow: 1 hours        // 1 hour window
        });
    }

    // Rate limiting check
    modifier checkRateLimit() {
        require(_checkAndUpdateRateLimit(msg.sender), "Rate limit exceeded");
        _;
    }

    // Trade size validation
    modifier validateTradeSize(uint256 amount) {
        require(amount >= protocolConfig.minTradeSize, "Trade too small");
        require(amount <= protocolConfig.maxTradeSize, "Trade too large");
        _;
    }

    // KYC check if required
    modifier requireKYC() {
        if (protocolConfig.requiresKYC) {
            require(kycApproved[msg.sender], "KYC required");
        }
        _;
    }

    function updateProtocolConfig(
        string memory parameter,
        uint256 value
    ) external onlyRole(GOVERNANCE_ROLE) {
        if (keccak256(bytes(parameter)) == keccak256(bytes("minTradeSize"))) {
            protocolConfig.minTradeSize = value;
        } else if (keccak256(bytes(parameter)) == keccak256(bytes("maxTradeSize"))) {
            protocolConfig.maxTradeSize = value;
        } // ... etc

        emit ConfigUpdated("protocol", parameter, value);
    }

    function updateSecurityConfig(
        string memory parameter,
        uint256 value
    ) external onlyRole(GOVERNANCE_ROLE) {
        if (keccak256(bytes(parameter)) == keccak256(bytes("maxGasPrice"))) {
            securityConfig.maxGasPrice = value;
        } // ... etc

        emit ConfigUpdated("security", parameter, value);
    }

    function _checkAndUpdateRateLimit(
        address user
    ) internal returns (bool) {
        if (block.timestamp >= lastTradeTimestamp[user] + securityConfig.timeWindow) {
            actionCount[user] = 1;
            lastTradeTimestamp[user] = block.timestamp;
            return true;
        }

        require(actionCount[user] < securityConfig.rateLimit, "Rate limit exceeded");
        actionCount[user]++;
        return true;
    }

    function updateKYCStatus(
        address user,
        bool status
    ) external onlyRole(OPERATOR_ROLE) {
        kycApproved[user] = status;
        emit KYCStatusUpdated(user, status);
    }

    function triggerCircuitBreaker(
        string memory reason
    ) external onlyRole(OPERATOR_ROLE) {
        _pause();
        emit CircuitBreakerTriggered(reason, block.timestamp);
    }

    // Additional functions would go here...
} 