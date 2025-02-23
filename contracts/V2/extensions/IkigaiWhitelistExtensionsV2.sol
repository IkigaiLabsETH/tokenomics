// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiWhitelistExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant WHITELIST_MANAGER = keccak256("WHITELIST_MANAGER");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    struct WhitelistConfig {
        uint256 maxUsers;         // Maximum users allowed
        uint256 minHoldTime;      // Minimum hold duration
        uint256 minTokens;        // Minimum tokens required
        uint256 startTime;        // Start timestamp
        bool requiresKYC;         // KYC requirement
    }

    struct UserStatus {
        bool isWhitelisted;       // Whitelist status
        uint256 joinTime;         // Join timestamp
        uint256 tokenBalance;     // Token balance
        uint256 lastUpdate;       // Last update time
        bool kycVerified;         // KYC verification
    }

    struct WhitelistStats {
        uint256 totalUsers;       // Total whitelisted users
        uint256 activeUsers;      // Active users
        uint256 kycVerified;      // KYC verified users
        uint256 totalTokens;      // Total tokens held
        uint256 lastUpdate;       // Last update time
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => WhitelistConfig) public whitelistConfigs;
    mapping(bytes32 => mapping(address => UserStatus)) public userStatus;
    mapping(bytes32 => WhitelistStats) public whitelistStats;
    mapping(address => bool) public globalWhitelist;
    
    uint256 public constant MIN_HOLD_TIME = 7 days;
    uint256 public constant MAX_USERS = 10000;
    uint256 public constant UPDATE_INTERVAL = 1 days;
    
    // Events
    event WhitelistConfigured(bytes32 indexed whitelistId, uint256 maxUsers);
    event UserWhitelisted(bytes32 indexed whitelistId, address indexed user);
    event UserRemoved(bytes32 indexed whitelistId, address indexed user);
    event KYCVerified(address indexed user, uint256 timestamp);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Whitelist configuration
    function configureWhitelist(
        bytes32 whitelistId,
        WhitelistConfig calldata config
    ) external onlyRole(WHITELIST_MANAGER) {
        require(config.maxUsers <= MAX_USERS, "Too many users");
        require(config.minHoldTime >= MIN_HOLD_TIME, "Hold time too short");
        require(config.minTokens > 0, "Invalid token requirement");
        
        whitelistConfigs[whitelistId] = config;
        
        emit WhitelistConfigured(whitelistId, config.maxUsers);
    }

    // User management
    function addToWhitelist(
        bytes32 whitelistId,
        address user
    ) external onlyRole(WHITELIST_MANAGER) {
        WhitelistConfig storage config = whitelistConfigs[whitelistId];
        WhitelistStats storage stats = whitelistStats[whitelistId];
        
        require(stats.totalUsers < config.maxUsers, "Whitelist full");
        require(!userStatus[whitelistId][user].isWhitelisted, "Already whitelisted");
        
        // Validate requirements
        require(
            _validateRequirements(whitelistId, user),
            "Requirements not met"
        );
        
        // Add user
        userStatus[whitelistId][user] = UserStatus({
            isWhitelisted: true,
            joinTime: block.timestamp,
            tokenBalance: _getTokenBalance(user),
            lastUpdate: block.timestamp,
            kycVerified: !config.requiresKYC || _isKYCVerified(user)
        });
        
        // Update stats
        stats.totalUsers++;
        stats.activeUsers++;
        stats.totalTokens += userStatus[whitelistId][user].tokenBalance;
        
        emit UserWhitelisted(whitelistId, user);
    }

    // KYC verification
    function verifyKYC(
        address user
    ) external onlyRole(VERIFIER_ROLE) {
        require(!_isKYCVerified(user), "Already verified");
        
        // Update user status
        bytes32[] memory whitelists = _getUserWhitelists(user);
        for (uint256 i = 0; i < whitelists.length; i++) {
            UserStatus storage status = userStatus[whitelists[i]][user];
            if (status.isWhitelisted) {
                status.kycVerified = true;
                whitelistStats[whitelists[i]].kycVerified++;
            }
        }
        
        emit KYCVerified(user, block.timestamp);
    }

    // Status updates
    function updateUserStatus(
        bytes32 whitelistId,
        address user
    ) external {
        UserStatus storage status = userStatus[whitelistId][user];
        require(status.isWhitelisted, "Not whitelisted");
        require(
            block.timestamp >= status.lastUpdate + UPDATE_INTERVAL,
            "Too frequent"
        );
        
        // Update token balance
        uint256 newBalance = _getTokenBalance(user);
        WhitelistStats storage stats = whitelistStats[whitelistId];
        stats.totalTokens = stats.totalTokens - status.tokenBalance + newBalance;
        status.tokenBalance = newBalance;
        
        // Check requirements
        if (!_validateRequirements(whitelistId, user)) {
            _removeFromWhitelist(whitelistId, user);
        }
        
        status.lastUpdate = block.timestamp;
    }

    // Internal functions
    function _validateRequirements(
        bytes32 whitelistId,
        address user
    ) internal view returns (bool) {
        WhitelistConfig storage config = whitelistConfigs[whitelistId];
        
        // Check token balance
        if (_getTokenBalance(user) < config.minTokens) {
            return false;
        }
        
        // Check KYC if required
        if (config.requiresKYC && !_isKYCVerified(user)) {
            return false;
        }
        
        return true;
    }

    function _removeFromWhitelist(
        bytes32 whitelistId,
        address user
    ) internal {
        UserStatus storage status = userStatus[whitelistId][user];
        WhitelistStats storage stats = whitelistStats[whitelistId];
        
        status.isWhitelisted = false;
        stats.activeUsers--;
        stats.totalTokens -= status.tokenBalance;
        
        if (status.kycVerified) {
            stats.kycVerified--;
        }
        
        emit UserRemoved(whitelistId, user);
    }

    function _getTokenBalance(
        address user
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _isKYCVerified(
        address user
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    function _getUserWhitelists(
        address user
    ) internal view returns (bytes32[] memory) {
        // Implementation needed
        return new bytes32[](0);
    }

    // View functions
    function getWhitelistConfig(
        bytes32 whitelistId
    ) external view returns (WhitelistConfig memory) {
        return whitelistConfigs[whitelistId];
    }

    function getUserStatus(
        bytes32 whitelistId,
        address user
    ) external view returns (UserStatus memory) {
        return userStatus[whitelistId][user];
    }

    function getWhitelistStats(
        bytes32 whitelistId
    ) external view returns (WhitelistStats memory) {
        return whitelistStats[whitelistId];
    }

    function isGloballyWhitelisted(
        address user
    ) external view returns (bool) {
        return globalWhitelist[user];
    }
} 