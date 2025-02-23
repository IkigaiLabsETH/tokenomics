// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiGovernanceV2.sol";
import "../interfaces/IIkigaiVaultV2.sol";

contract IkigaiTimelockExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant TIMELOCK_MANAGER = keccak256("TIMELOCK_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct TimelockOperation {
        bytes32 id;              // Operation ID
        address target;          // Target contract
        uint256 value;          // ETH value
        bytes data;             // Call data
        uint256 timestamp;      // Queue timestamp
        bool executed;          // Execution status
        bool canceled;          // Cancellation status
    }

    struct TimelockConfig {
        uint256 delay;          // Timelock delay
        uint256 gracePeriod;    // Execution grace period
        uint256 minDelay;       // Minimum delay
        uint256 maxDelay;       // Maximum delay
        bool requiresApproval;  // Approval requirement
    }

    struct ExecutionWindow {
        uint256 start;          // Start timestamp
        uint256 end;            // End timestamp
        bool isOpen;            // Window status
        bool requiresVote;      // Vote requirement
        uint256 minApprovals;   // Required approvals
    }

    // State variables
    IIkigaiGovernanceV2 public governance;
    IIkigaiVaultV2 public vault;
    
    mapping(bytes32 => TimelockOperation) public operations;
    mapping(bytes32 => TimelockConfig) public timelockConfigs;
    mapping(bytes32 => ExecutionWindow) public executionWindows;
    mapping(bytes32 => mapping(address => bool)) public approvals;
    
    uint256 public constant MIN_DELAY = 1 days;
    uint256 public constant MAX_DELAY = 30 days;
    uint256 public constant GRACE_PERIOD = 14 days;
    
    // Events
    event OperationQueued(bytes32 indexed id, address target, uint256 timestamp);
    event OperationExecuted(bytes32 indexed id, address executor);
    event OperationCanceled(bytes32 indexed id, string reason);
    event ConfigUpdated(bytes32 indexed configId, uint256 delay);

    constructor(
        address _governance,
        address _vault
    ) {
        governance = IIkigaiGovernanceV2(_governance);
        vault = IIkigaiVaultV2(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Configuration management
    function configureTimelock(
        bytes32 configId,
        TimelockConfig calldata config
    ) external onlyRole(TIMELOCK_MANAGER) {
        require(config.delay >= MIN_DELAY, "Delay too short");
        require(config.delay <= MAX_DELAY, "Delay too long");
        require(config.gracePeriod <= GRACE_PERIOD, "Grace period too long");
        
        timelockConfigs[configId] = config;
        
        emit ConfigUpdated(configId, config.delay);
    }

    // Operation queueing
    function queueOperation(
        bytes32 configId,
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyRole(TIMELOCK_MANAGER) returns (bytes32) {
        TimelockConfig storage config = timelockConfigs[configId];
        require(config.delay > 0, "Invalid config");
        
        bytes32 id = keccak256(
            abi.encode(
                target,
                value,
                data,
                block.timestamp
            )
        );
        
        require(operations[id].timestamp == 0, "Operation exists");
        
        // Create operation
        operations[id] = TimelockOperation({
            id: id,
            target: target,
            value: value,
            data: data,
            timestamp: block.timestamp + config.delay,
            executed: false,
            canceled: false
        });
        
        // Set execution window
        executionWindows[id] = ExecutionWindow({
            start: block.timestamp + config.delay,
            end: block.timestamp + config.delay + config.gracePeriod,
            isOpen: true,
            requiresVote: config.requiresApproval,
            minApprovals: _calculateMinApprovals(configId)
        });
        
        emit OperationQueued(id, target, block.timestamp + config.delay);
        return id;
    }

    // Operation execution
    function executeOperation(
        bytes32 operationId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        TimelockOperation storage operation = operations[operationId];
        ExecutionWindow storage window = executionWindows[operationId];
        
        require(!operation.executed && !operation.canceled, "Invalid status");
        require(block.timestamp >= operation.timestamp, "Too early");
        require(block.timestamp <= window.end, "Too late");
        
        if (window.requiresVote) {
            require(
                _getApprovalCount(operationId) >= window.minApprovals,
                "Insufficient approvals"
            );
        }
        
        // Execute operation
        (bool success, ) = operation.target.call{value: operation.value}(
            operation.data
        );
        require(success, "Execution failed");
        
        // Update status
        operation.executed = true;
        window.isOpen = false;
        
        emit OperationExecuted(operationId, msg.sender);
    }

    // Operation approval
    function approveOperation(
        bytes32 operationId
    ) external onlyRole(TIMELOCK_MANAGER) {
        TimelockOperation storage operation = operations[operationId];
        ExecutionWindow storage window = executionWindows[operationId];
        
        require(!operation.executed && !operation.canceled, "Invalid status");
        require(window.requiresVote, "Approval not required");
        require(!approvals[operationId][msg.sender], "Already approved");
        
        approvals[operationId][msg.sender] = true;
    }

    // Internal functions
    function _calculateMinApprovals(
        bytes32 configId
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _getApprovalCount(
        bytes32 operationId
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _validateOperation(
        bytes32 operationId
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    // View functions
    function getOperation(
        bytes32 operationId
    ) external view returns (TimelockOperation memory) {
        return operations[operationId];
    }

    function getTimelockConfig(
        bytes32 configId
    ) external view returns (TimelockConfig memory) {
        return timelockConfigs[configId];
    }

    function getExecutionWindow(
        bytes32 operationId
    ) external view returns (ExecutionWindow memory) {
        return executionWindows[operationId];
    }

    function isApproved(
        bytes32 operationId,
        address approver
    ) external view returns (bool) {
        return approvals[operationId][approver];
    }
} 