// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiStrategyExtensionsV2.sol";
import "../interfaces/IIkigaiVaultV2.sol";

contract IkigaiKeeperExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant KEEPER_MANAGER = keccak256("KEEPER_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct KeeperTask {
        bytes32 taskType;         // Type of task
        uint256 interval;         // Execution interval
        uint256 lastExecution;    // Last execution time
        uint256 gasLimit;         // Maximum gas allowed
        address target;           // Target contract
        bytes data;              // Task call data
        bool isActive;           // Whether task is active
    }

    struct KeeperStats {
        uint256 totalExecutions;  // Total executions
        uint256 successRate;      // Success rate (basis points)
        uint256 avgGasUsed;      // Average gas used
        uint256 totalRevenue;     // Total revenue earned
        uint256 lastPayment;      // Last payment timestamp
    }

    struct TaskResult {
        bool success;            // Execution success
        uint256 gasUsed;        // Gas used
        bytes returnData;       // Return data
        uint256 timestamp;      // Execution time
        string error;           // Error message if any
    }

    // State variables
    IIkigaiStrategyExtensionsV2 public strategyExtensions;
    IIkigaiVaultV2 public vault;
    
    mapping(bytes32 => KeeperTask) public keeperTasks;
    mapping(address => KeeperStats) public keeperStats;
    mapping(bytes32 => TaskResult) public taskResults;
    mapping(address => bool) public registeredKeepers;
    
    uint256 public constant MIN_INTERVAL = 1 minutes;
    uint256 public constant MAX_GAS_LIMIT = 2_000_000;
    uint256 public constant MIN_SUCCESS_RATE = 9500; // 95%
    
    // Events
    event TaskCreated(bytes32 indexed taskId, bytes32 taskType);
    event TaskExecuted(bytes32 indexed taskId, bool success);
    event KeeperRegistered(address indexed keeper, bool status);
    event TaskAlert(bytes32 indexed taskId, string message);

    constructor(
        address _strategyExtensions,
        address _vault
    ) {
        strategyExtensions = IIkigaiStrategyExtensionsV2(_strategyExtensions);
        vault = IIkigaiVaultV2(_vault);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Task management
    function createTask(
        bytes32 taskType,
        uint256 interval,
        uint256 gasLimit,
        address target,
        bytes calldata data
    ) external onlyRole(KEEPER_MANAGER) returns (bytes32) {
        require(interval >= MIN_INTERVAL, "Interval too short");
        require(gasLimit <= MAX_GAS_LIMIT, "Gas limit too high");
        require(target != address(0), "Invalid target");
        
        bytes32 taskId = keccak256(abi.encodePacked(
            taskType,
            target,
            block.timestamp
        ));
        
        keeperTasks[taskId] = KeeperTask({
            taskType: taskType,
            interval: interval,
            lastExecution: block.timestamp,
            gasLimit: gasLimit,
            target: target,
            data: data,
            isActive: true
        });
        
        emit TaskCreated(taskId, taskType);
        return taskId;
    }

    // Task execution
    function executeTask(
        bytes32 taskId
    ) external onlyRole(EXECUTOR_ROLE) nonReentrant {
        require(registeredKeepers[msg.sender], "Not registered");
        
        KeeperTask storage task = keeperTasks[taskId];
        require(task.isActive, "Task not active");
        require(
            block.timestamp >= task.lastExecution + task.interval,
            "Too early"
        );
        
        // Track gas usage
        uint256 startGas = gasleft();
        
        // Execute task
        (bool success, bytes memory returnData) = task.target.call{
            gas: task.gasLimit
        }(task.data);
        
        // Calculate gas used
        uint256 gasUsed = startGas - gasleft();
        
        // Update task result
        taskResults[taskId] = TaskResult({
            success: success,
            gasUsed: gasUsed,
            returnData: returnData,
            timestamp: block.timestamp,
            error: success ? "" : _getRevertMsg(returnData)
        });
        
        // Update keeper stats
        _updateKeeperStats(msg.sender, success, gasUsed);
        
        // Update task
        task.lastExecution = block.timestamp;
        
        emit TaskExecuted(taskId, success);
        
        // Handle failures
        if (!success) {
            emit TaskAlert(taskId, "Execution failed");
            _handleTaskFailure(taskId);
        }
    }

    // Keeper management
    function registerKeeper(
        address keeper,
        bool status
    ) external onlyRole(KEEPER_MANAGER) {
        require(keeper != address(0), "Invalid keeper");
        
        if (status) {
            require(
                keeperStats[keeper].successRate >= MIN_SUCCESS_RATE,
                "Success rate too low"
            );
        }
        
        registeredKeepers[keeper] = status;
        emit KeeperRegistered(keeper, status);
    }

    // Internal functions
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
    }

    function _handleTaskFailure(bytes32 taskId) internal {
        KeeperTask storage task = keeperTasks[taskId];
        TaskResult storage result = taskResults[taskId];
        
        // Check for repeated failures
        if (_isRepeatedFailure(taskId)) {
            task.isActive = false;
            emit TaskAlert(taskId, "Task disabled due to repeated failures");
        }
        
        // Log failure details
        emit TaskAlert(taskId, result.error);
    }

    function _isRepeatedFailure(
        bytes32 taskId
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    function _getRevertMsg(
        bytes memory returnData
    ) internal pure returns (string memory) {
        // Implementation needed
        return "";
    }

    // View functions
    function getTask(
        bytes32 taskId
    ) external view returns (KeeperTask memory) {
        return keeperTasks[taskId];
    }

    function getKeeperStats(
        address keeper
    ) external view returns (KeeperStats memory) {
        return keeperStats[keeper];
    }

    function getTaskResult(
        bytes32 taskId
    ) external view returns (TaskResult memory) {
        return taskResults[taskId];
    }

    function isKeeperRegistered(
        address keeper
    ) external view returns (bool) {
        return registeredKeepers[keeper];
    }
} 