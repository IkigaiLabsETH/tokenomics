// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiGovernanceV2.sol";

contract IkigaiTreasuryExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TREASURY_MANAGER = keccak256("TREASURY_MANAGER");
    bytes32 public constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");

    struct TreasuryAsset {
        uint256 balance;          // Current balance
        uint256 allocated;        // Amount allocated
        uint256 reserved;         // Amount reserved
        uint256 lastUpdate;       // Last update time
        bool isActive;            // Whether asset is active
    }

    struct Allocation {
        address recipient;        // Recipient address
        uint256 amount;          // Allocated amount
        uint256 releaseTime;     // Release timestamp
        string purpose;          // Allocation purpose
        bool executed;           // Whether executed
        bool canceled;           // Whether canceled
    }

    struct SpendingLimit {
        uint256 daily;           // Daily limit
        uint256 monthly;         // Monthly limit
        uint256 emergency;       // Emergency limit
        uint256 lastReset;       // Last reset time
        uint256 spent;           // Amount spent
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    IIkigaiVaultV2 public vault;
    IIkigaiGovernanceV2 public governance;
    
    mapping(address => TreasuryAsset) public treasuryAssets;
    mapping(bytes32 => Allocation) public allocations;
    mapping(address => SpendingLimit) public spendingLimits;
    mapping(address => bool) public whitelistedTokens;
    
    uint256 public allocationCount;
    uint256 public constant MIN_TIMELOCK = 2 days;
    uint256 public constant MAX_ALLOCATION = 1000000 * 1e18; // 1M tokens
    
    // Events
    event AssetRegistered(address indexed token, uint256 initialBalance);
    event AllocationCreated(bytes32 indexed allocationId, address recipient);
    event AllocationExecuted(bytes32 indexed allocationId, uint256 amount);
    event EmergencyWithdrawal(address indexed token, uint256 amount);

    constructor(
        address _ikigaiToken,
        address _vault,
        address _governance
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        vault = IIkigaiVaultV2(_vault);
        governance = IIkigaiGovernanceV2(_governance);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Asset management
    function registerAsset(
        address token,
        bool isWhitelisted
    ) external onlyRole(TREASURY_MANAGER) {
        require(!treasuryAssets[token].isActive, "Asset exists");
        
        uint256 balance = IERC20(token).balanceOf(address(this));
        
        treasuryAssets[token] = TreasuryAsset({
            balance: balance,
            allocated: 0,
            reserved: 0,
            lastUpdate: block.timestamp,
            isActive: true
        });
        
        whitelistedTokens[token] = isWhitelisted;
        
        emit AssetRegistered(token, balance);
    }

    // Allocation management
    function createAllocation(
        address token,
        address recipient,
        uint256 amount,
        uint256 releaseTime,
        string calldata purpose
    ) external onlyRole(ALLOCATOR_ROLE) returns (bytes32) {
        require(treasuryAssets[token].isActive, "Asset not registered");
        require(releaseTime >= block.timestamp + MIN_TIMELOCK, "Release too soon");
        require(amount <= MAX_ALLOCATION, "Amount too large");
        
        TreasuryAsset storage asset = treasuryAssets[token];
        require(
            amount <= asset.balance - asset.allocated,
            "Insufficient balance"
        );
        
        bytes32 allocationId = keccak256(abi.encodePacked(
            token,
            recipient,
            block.timestamp,
            allocationCount++
        ));
        
        allocations[allocationId] = Allocation({
            recipient: recipient,
            amount: amount,
            releaseTime: releaseTime,
            purpose: purpose,
            executed: false,
            canceled: false
        });
        
        asset.allocated += amount;
        
        emit AllocationCreated(allocationId, recipient);
        return allocationId;
    }

    // Allocation execution
    function executeAllocation(
        bytes32 allocationId
    ) external nonReentrant {
        Allocation storage allocation = allocations[allocationId];
        require(!allocation.executed && !allocation.canceled, "Invalid status");
        require(block.timestamp >= allocation.releaseTime, "Too early");
        
        allocation.executed = true;
        
        // Update spending tracking
        _updateSpending(allocation.recipient, allocation.amount);
        
        // Transfer tokens
        require(
            IERC20(ikigaiToken).transfer(
                allocation.recipient,
                allocation.amount
            ),
            "Transfer failed"
        );
        
        emit AllocationExecuted(allocationId, allocation.amount);
    }

    // Emergency functions
    function emergencyWithdraw(
        address token,
        uint256 amount
    ) external onlyRole(TREASURY_MANAGER) {
        require(
            governance.hasEmergencyAccess(msg.sender),
            "No emergency access"
        );
        
        TreasuryAsset storage asset = treasuryAssets[token];
        require(asset.isActive, "Asset not registered");
        require(amount <= asset.balance - asset.allocated, "Insufficient funds");
        
        // Transfer tokens
        require(
            IERC20(token).transfer(msg.sender, amount),
            "Transfer failed"
        );
        
        asset.balance -= amount;
        
        emit EmergencyWithdrawal(token, amount);
    }

    // Internal functions
    function _updateSpending(
        address spender,
        uint256 amount
    ) internal {
        SpendingLimit storage limit = spendingLimits[spender];
        
        // Reset limits if needed
        if (block.timestamp >= limit.lastReset + 30 days) {
            limit.spent = 0;
            limit.lastReset = block.timestamp;
        }
        
        // Update spent amount
        limit.spent += amount;
        
        // Check limits
        require(limit.spent <= limit.monthly, "Monthly limit exceeded");
        require(
            amount <= limit.emergency || !governance.isEmergencyActive(),
            "Emergency limit exceeded"
        );
    }

    // View functions
    function getAssetInfo(
        address token
    ) external view returns (TreasuryAsset memory) {
        return treasuryAssets[token];
    }

    function getAllocation(
        bytes32 allocationId
    ) external view returns (Allocation memory) {
        return allocations[allocationId];
    }

    function getSpendingLimit(
        address spender
    ) external view returns (SpendingLimit memory) {
        return spendingLimits[spender];
    }

    function isTokenWhitelisted(
        address token
    ) external view returns (bool) {
        return whitelistedTokens[token];
    }
} 