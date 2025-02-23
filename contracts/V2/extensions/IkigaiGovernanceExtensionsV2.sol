// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiTimelockV2.sol";

contract IkigaiGovernanceExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant GOVERNANCE_MANAGER = keccak256("GOVERNANCE_MANAGER");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    struct Proposal {
        bytes32 id;              // Proposal ID
        string title;            // Proposal title
        string description;      // Proposal description
        address[] targets;       // Target contracts
        uint256[] values;        // ETH values
        bytes[] calldatas;       // Call data array
        uint256 startBlock;      // Start block
        uint256 endBlock;        // End block
        bool executed;           // Execution status
        bool canceled;           // Cancellation status
    }

    struct Vote {
        bool support;            // Support status
        uint256 votes;           // Vote weight
        string reason;           // Vote reason
        uint256 timestamp;       // Vote time
    }

    struct ProposalConfig {
        uint256 threshold;       // Proposal threshold
        uint256 quorum;          // Required quorum
        uint256 votingDelay;     // Blocks before voting
        uint256 votingPeriod;    // Voting duration
        bool requiresTimelock;   // Timelock requirement
    }

    // State variables
    IIkigaiVaultV2 public vault;
    IIkigaiTimelockV2 public timelock;
    IERC20 public governanceToken;
    
    mapping(bytes32 => Proposal) public proposals;
    mapping(bytes32 => mapping(address => Vote)) public votes;
    mapping(bytes32 => ProposalConfig) public proposalConfigs;
    mapping(address => uint256) public proposalPowers;
    
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 100000e18; // 100k tokens
    uint256 public constant MIN_VOTING_PERIOD = 5760; // ~24 hours
    uint256 public constant MAX_VOTING_PERIOD = 40320; // ~1 week
    
    // Events
    event ProposalCreated(bytes32 indexed proposalId, address proposer);
    event VoteCast(bytes32 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(bytes32 indexed proposalId);
    event ProposalCanceled(bytes32 indexed proposalId);

    constructor(
        address _vault,
        address _timelock,
        address _governanceToken
    ) {
        vault = IIkigaiVaultV2(_vault);
        timelock = IIkigaiTimelockV2(_timelock);
        governanceToken = IERC20(_governanceToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Proposal management
    function createProposal(
        string calldata title,
        string calldata description,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external onlyRole(PROPOSER_ROLE) returns (bytes32) {
        require(targets.length > 0, "Empty proposal");
        require(
            targets.length == values.length &&
            targets.length == calldatas.length,
            "Array length mismatch"
        );
        
        bytes32 proposalId = keccak256(
            abi.encode(
                title,
                targets,
                values,
                calldatas,
                block.number
            )
        );
        
        require(!proposals[proposalId].executed, "Already exists");
        
        ProposalConfig storage config = proposalConfigs[proposalId];
        require(
            proposalPowers[msg.sender] >= config.threshold,
            "Below threshold"
        );
        
        // Create proposal
        proposals[proposalId] = Proposal({
            id: proposalId,
            title: title,
            description: description,
            targets: targets,
            values: values,
            calldatas: calldatas,
            startBlock: block.number + config.votingDelay,
            endBlock: block.number + config.votingDelay + config.votingPeriod,
            executed: false,
            canceled: false
        });
        
        emit ProposalCreated(proposalId, msg.sender);
        return proposalId;
    }

    // Voting
    function castVote(
        bytes32 proposalId,
        bool support,
        string calldata reason
    ) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed && !proposal.canceled, "Invalid status");
        require(
            block.number >= proposal.startBlock &&
            block.number <= proposal.endBlock,
            "Not in voting period"
        );
        
        uint256 votes = governanceToken.balanceOf(msg.sender);
        require(votes > 0, "No voting power");
        
        // Record vote
        votes[proposalId][msg.sender] = Vote({
            support: support,
            votes: votes,
            reason: reason,
            timestamp: block.timestamp
        });
        
        emit VoteCast(proposalId, msg.sender, support);
    }

    // Proposal execution
    function executeProposal(
        bytes32 proposalId
    ) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed && !proposal.canceled, "Invalid status");
        require(block.number > proposal.endBlock, "Voting ongoing");
        
        ProposalConfig storage config = proposalConfigs[proposalId];
        require(
            _getVotes(proposalId, true) >= config.quorum,
            "Quorum not reached"
        );
        
        if (config.requiresTimelock) {
            // Queue in timelock
            timelock.queueOperations(
                proposal.targets,
                proposal.values,
                proposal.calldatas
            );
        } else {
            // Direct execution
            _executeProposal(proposal);
        }
        
        proposal.executed = true;
        emit ProposalExecuted(proposalId);
    }

    // Internal functions
    function _executeProposal(
        Proposal storage proposal
    ) internal {
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            (bool success,) = proposal.targets[i].call{value: proposal.values[i]}(
                proposal.calldatas[i]
            );
            require(success, "Execution failed");
        }
    }

    function _getVotes(
        bytes32 proposalId,
        bool support
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _validateProposal(
        bytes32 proposalId
    ) internal view returns (bool) {
        // Implementation needed
        return false;
    }

    // View functions
    function getProposal(
        bytes32 proposalId
    ) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getVote(
        bytes32 proposalId,
        address voter
    ) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }

    function getProposalConfig(
        bytes32 proposalId
    ) external view returns (ProposalConfig memory) {
        return proposalConfigs[proposalId];
    }

    function getProposalPower(
        address proposer
    ) external view returns (uint256) {
        return proposalPowers[proposer];
    }
} 