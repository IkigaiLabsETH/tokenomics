// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiNFTTradingExtensionsV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiAutomationExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant AUTOMATION_MANAGER = keccak256("AUTOMATION_MANAGER");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct AutomationTask {
        bytes32 taskType;         // Type of automation task
        uint256 interval;         // Execution interval
        uint256 lastExecution;    // Last execution timestamp
        bytes parameters;         // Task parameters
        bool isActive;           // Whether task is active
    }

    struct TaskResult {
        bool success;            // Whether execution succeeded
        uint256 gasUsed;        // Gas used in execution
        string message;         // Result message
        uint256 timestamp;      // Execution timestamp
    }

    struct KeeperStats {
        uint256 totalExecutions;  // Total tasks executed
        uint256 successRate;      // Success rate (basis points)
        uint256 avgGasUsed;      // Average gas used
        uint256 lastActive;       // Last active timestamp
        bool isActive;           // Whether keeper is active
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiNFTTradingExtensionsV2 public trading;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => AutomationTask) public tasks;
    mapping(bytes32 => TaskResult) public taskResults;
    mapping(address => KeeperStats) public keeperStats;
    
    uint256 public constant MIN_INTERVAL = 1 minutes;
    uint256 public constant MAX_INTERVAL = 1 days;
    uint256 public constant MIN_SUCCESS_RATE = 9500; // 95%
    
    // Events
    event TaskCreated(bytes32 indexed taskId, bytes32 taskType);
    event TaskExecuted(bytes32 indexed taskId, bool success);
    event KeeperUpdated(address indexed keeper, bool isActive);
    event AutomationAlert(bytes32 indexed taskId, string message);

    constructor(
        address _marketplace,
        address _trading,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        trading = IIkigaiNFTTradingExtensionsV2(_trading);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Task management
    function createAutomationTask(
        bytes32 taskId,
        bytes32 taskType,
        uint256 interval,
        bytes calldata parameters
    ) external onlyRole(AUTOMATION_MANAGER) {
        require(!tasks[taskId].isActive, "Task exists");
        require(interval >= MIN_INTERVAL, "Interval too short");
        require(interval <= MAX_INTERVAL, "Interval too long");
        
        tasks[taskId] = AutomationTask({
            taskType: taskType,
            interval: interval,
            lastExecution: block.timestamp,
            parameters: parameters,
            isActive: true
        });
        
        emit TaskCreated(taskId, taskType);
    }

    // Task execution
    function executeTask(
        bytes32 taskId
    ) external onlyRole(KEEPER_ROLE) nonReentrant whenNotPaused {
        AutomationTask storage task = tasks[taskId];
        require(task.isActive, "Task not active");
        require(
            block.timestamp >= task.lastExecution + task.interval,
            "Too early"
        );
        
        // Track gas usage
        uint256 startGas = gasleft();
        
        // Execute task based on type
        bool success;
        string memory message;
        
        if (task.taskType == "UPDATE_METRICS") {
            (success, message) = _executeMetricsUpdate(task.parameters);
        } else if (task.taskType == "CHECK_POSITIONS") {
            (success, message) = _checkTradingPositions(task.parameters);
        } else if (task.taskType == "REBALANCE") {
            (success, message) = _executeRebalancing(task.parameters);
        } else {
            revert("Unknown task type");
        }
        
        // Update task result
        uint256 gasUsed = startGas - gasleft();
        taskResults[taskId] = TaskResult({
            success: success,
            gasUsed: gasUsed,
            message: message,
            timestamp: block.timestamp
        });
        
        // Update keeper stats
        _updateKeeperStats(msg.sender, success, gasUsed);
        
        // Update task timestamp
        task.lastExecution = block.timestamp;
        
        emit TaskExecuted(taskId, success);
        
        // Check for alerts
        if (!success) {
            emit AutomationAlert(taskId, message);
        }
    }

    // Keeper management
    function updateKeeper(
        address keeper,
        bool isActive
    ) external onlyRole(AUTOMATION_MANAGER) {
        require(keeper != address(0), "Invalid keeper");
        
        KeeperStats storage stats = keeperStats[keeper];
        
        if (isActive) {
            require(
                stats.successRate >= MIN_SUCCESS_RATE,
                "Success rate too low"
            );
            grantRole(KEEPER_ROLE, keeper);
        } else {
            revokeRole(KEEPER_ROLE, keeper);
        }
        
        stats.isActive = isActive;
        emit KeeperUpdated(keeper, isActive);
    }

    // Internal task execution functions
    function _executeMetricsUpdate(
        bytes memory parameters
    ) internal returns (bool success, string memory message) {
        try trading.updateCollectionMetrics(
            abi.decode(parameters, (address))
        ) {
            return (true, "Metrics updated");
        } catch Error(string memory err) {
            return (false, err);
        }
    }

    function _checkTradingPositions(
        bytes memory parameters
    ) internal returns (bool success, string memory message) {
        // Implementation needed
        return (false, "Not implemented");
    }

    function _executeRebalancing(
        bytes memory parameters
    ) internal returns (bool success, string memory message) {
        // Implementation needed
        return (false, "Not implemented");
    }

    function _updateKeeperStats(
        address keeper,
        bool success,
        uint256 gasUsed
    ) internal {
        KeeperStats storage stats = keeperStats[keeper];
        
        // Update execution count
        stats.totalExecutions++;
        
        // Update success rate
        if (success) {
            stats.successRate = (stats.successRate * (stats.totalExecutions - 1) + 10000) 
                / stats.totalExecutions;
        } else {
            stats.successRate = (stats.successRate * (stats.totalExecutions - 1)) 
                / stats.totalExecutions;
        }
        
        // Update gas stats
        stats.avgGasUsed = (stats.avgGasUsed * (stats.totalExecutions - 1) + gasUsed) 
            / stats.totalExecutions;
        
        stats.lastActive = block.timestamp;
    }

    // View functions
    function getTaskInfo(
        bytes32 taskId
    ) external view returns (AutomationTask memory) {
        return tasks[taskId];
    }

    function getTaskResult(
        bytes32 taskId
    ) external view returns (TaskResult memory) {
        return taskResults[taskId];
    }

    function getKeeperStats(
        address keeper
    ) external view returns (KeeperStats memory) {
        return keeperStats[keeper];
    }

    function getExecutableTasks() external view returns (bytes32[] memory) {
        // Implementation needed
        return new bytes32[](0);
    }
} 