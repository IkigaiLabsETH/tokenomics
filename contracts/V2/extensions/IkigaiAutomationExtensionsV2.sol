// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IIkigaiMarketplaceV2.sol";
import "../interfaces/IIkigaiOracleV2.sol";

contract IkigaiAutomationExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant AUTOMATION_MANAGER = keccak256("AUTOMATION_MANAGER");
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    struct Task {
        bytes32 id;              // Task ID
        address target;          // Target contract
        bytes data;             // Call data
        uint256 interval;       // Execution interval
        uint256 lastRun;        // Last execution time
        bool isActive;          // Task status
    }

    struct KeeperStats {
        uint256 executions;      // Total executions
        uint256 failures;        // Failed executions
        uint256 gasUsed;        // Total gas used
        uint256 rewards;        // Total rewards
        uint256 lastAction;     // Last action time
    }

    struct ExecutionConfig {
        uint256 maxGas;         // Maximum gas
        uint256 reward;         // Keeper reward
        uint256 delay;          // Minimum delay
        uint256 timeout;        // Execution timeout
        bool requiresApproval;  // Approval requirement
    }

    // State variables
    IIkigaiMarketplaceV2 public marketplace;
    IIkigaiOracleV2 public oracle;
    
    mapping(bytes32 => Task) public tasks;
    mapping(address => KeeperStats) public keeperStats;
    mapping(bytes32 => ExecutionConfig) public executionConfigs;
    mapping(address => bool) public whitelistedKeepers;
    
    uint256 public constant MAX_GAS = 5000000;
    uint256 public constant MIN_INTERVAL = 1 minutes;
    uint256 public constant MAX_REWARD = 1 ether;
    
    // Events
    event TaskCreated(bytes32 indexed taskId, address target);
    event TaskExecuted(bytes32 indexed taskId, address keeper);
    event TaskFailed(bytes32 indexed taskId, string reason);
    event KeeperRewarded(address indexed keeper, uint256 amount);

    constructor(
        address _marketplace,
        address _oracle
    ) {
        marketplace = IIkigaiMarketplaceV2(_marketplace);
        oracle = IIkigaiOracleV2(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Task management
    function createTask(
        bytes32 taskId,
        address target,
        bytes calldata data,
        uint256 interval
    ) external onlyRole(AUTOMATION_MANAGER) {
        require(!tasks[taskId].isActive, "Task exists");
        require(target != address(0), "Invalid target");
        require(interval >= MIN_INTERVAL, "Interval too short");
        
        tasks[taskId] = Task({
            id: taskId,
            target: target,
            data: data,
            interval: interval,
            lastRun: block.timestamp,
            isActive: true
        });
        
        emit TaskCreated(taskId, target);
    }

    // Task execution
    function executeTask(
        bytes32 taskId
    ) external onlyRole(KEEPER_ROLE) nonReentrant {
        require(whitelistedKeepers[msg.sender], "Not whitelisted");
        
        Task storage task = tasks[taskId];
        require(task.isActive, "Task not active");
        require(
            block.timestamp >= task.lastRun + task.interval,
            "Too early"
        );
        
        ExecutionConfig storage config = executionConfigs[taskId];
        uint256 startGas = gasleft();
        
        // Execute task
        try IIkigaiMarketplaceV2(task.target).functionCall(task.data) {
            // Update stats
            task.lastRun = block.timestamp;
            
            uint256 gasUsed = startGas - gasleft();
            _updateKeeperStats(msg.sender, gasUsed, true);
            
            // Reward keeper
            _rewardKeeper(msg.sender, config.reward);
            
            emit TaskExecuted(taskId, msg.sender);
        } catch Error(string memory reason) {
            _updateKeeperStats(msg.sender, startGas - gasleft(), false);
            emit TaskFailed(taskId, reason);
        }
    }

    // Keeper management
    function updateKeeperStatus(
        address keeper,
        bool status
    ) external onlyRole(AUTOMATION_MANAGER) {
        whitelistedKeepers[keeper] = status;
    }

    // Internal functions
    function _updateKeeperStats(
        address keeper,
        uint256 gasUsed,
        bool success
    ) internal {
        KeeperStats storage stats = keeperStats[keeper];
        
        stats.executions++;
        stats.gasUsed += gasUsed;
        stats.lastAction = block.timestamp;
        
        if (!success) {
            stats.failures++;
        }
    }

    function _rewardKeeper(
        address keeper,
        uint256 amount
    ) internal {
        require(amount <= MAX_REWARD, "Reward too high");
        
        KeeperStats storage stats = keeperStats[keeper];
        stats.rewards += amount;
        
        // Transfer reward
        payable(keeper).transfer(amount);
        
        emit KeeperRewarded(keeper, amount);
    }

    function _validateExecution(
        bytes32 taskId,
        address keeper
    ) internal view returns (bool) {
        ExecutionConfig storage config = executionConfigs[taskId];
        
        if (config.requiresApproval) {
            // Check approval
            // Implementation needed
        }
        
        return true;
    }

    // View functions
    function getTask(
        bytes32 taskId
    ) external view returns (Task memory) {
        return tasks[taskId];
    }

    function getKeeperStats(
        address keeper
    ) external view returns (KeeperStats memory) {
        return keeperStats[keeper];
    }

    function getExecutionConfig(
        bytes32 taskId
    ) external view returns (ExecutionConfig memory) {
        return executionConfigs[taskId];
    }

    function isKeeperWhitelisted(
        address keeper
    ) external view returns (bool) {
        return whitelistedKeepers[keeper];
    }
} 