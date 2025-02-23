// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiGovernanceV2.sol";
import "../interfaces/IIkigaiStakingV2.sol";

contract IkigaiVotingExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant VOTING_MANAGER = keccak256("VOTING_MANAGER");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    struct Proposal {
        string title;             // Proposal title
        string description;       // Proposal description
        uint256 startTime;        // Start timestamp
        uint256 endTime;          // End timestamp
        uint256 quorum;          // Required quorum
        bool executed;            // Execution status
        bool canceled;            // Cancellation status
    }

    struct Vote {
        bool support;            // Support status
        uint256 power;           // Voting power
        uint256 timestamp;       // Vote timestamp
        string reason;           // Vote reason
    }

    struct VotingPower {
        uint256 tokenPower;      // Power from tokens
        uint256 stakingPower;    // Power from staking
        uint256 nftPower;        // Power from NFTs
        uint256 delegatedPower;  // Delegated power
        uint256 lastUpdate;      // Last update time
    }

    // State variables
    IIkigaiGovernanceV2 public governance;
    IIkigaiStakingV2 public staking;
    IERC20 public votingToken;
    
    mapping(bytes32 => Proposal) public proposals;
    mapping(bytes32 => mapping(address => Vote)) public votes;
    mapping(address => VotingPower) public votingPower;
    mapping(address => address) public delegates;
    
    uint256 public constant MIN_PROPOSAL_DURATION = 3 days;
    uint256 public constant MAX_PROPOSAL_DURATION = 14 days;
    uint256 public constant MIN_QUORUM = 1000; // 10%
    
    // Events
    event ProposalCreated(bytes32 indexed proposalId, string title);
    event VoteCast(bytes32 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(bytes32 indexed proposalId);
    event VotingPowerUpdated(address indexed user, uint256 newPower);

    constructor(
        address _governance,
        address _staking,
        address _votingToken
    ) {
        governance = IIkigaiGovernanceV2(_governance);
        staking = IIkigaiStakingV2(_staking);
        votingToken = IERC20(_votingToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Proposal management
    function createProposal(
        bytes32 proposalId,
        string calldata title,
        string calldata description,
        uint256 duration,
        uint256 quorum
    ) external onlyRole(VOTING_MANAGER) {
        require(duration >= MIN_PROPOSAL_DURATION, "Duration too short");
        require(duration <= MAX_PROPOSAL_DURATION, "Duration too long");
        require(quorum >= MIN_QUORUM, "Quorum too low");
        
        proposals[proposalId] = Proposal({
            title: title,
            description: description,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            quorum: quorum,
            executed: false,
            canceled: false
        });
        
        emit ProposalCreated(proposalId, title);
    }

    // Voting
    function castVote(
        bytes32 proposalId,
        bool support,
        string calldata reason
    ) external nonReentrant whenNotPaused {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.executed && !proposal.canceled, "Proposal not active");
        require(
            block.timestamp >= proposal.startTime &&
            block.timestamp <= proposal.endTime,
            "Not in voting period"
        );
        
        uint256 power = _getVotingPower(msg.sender);
        require(power > 0, "No voting power");
        
        // Record vote
        votes[proposalId][msg.sender] = Vote({
            support: support,
            power: power,
            timestamp: block.timestamp,
            reason: reason
        });
        
        emit VoteCast(proposalId, msg.sender, support);
    }

    // Power delegation
    function delegate(address delegatee) external {
        require(delegatee != msg.sender, "Self delegation");
        
        address currentDelegate = delegates[msg.sender];
        delegates[msg.sender] = delegatee;
        
        if (currentDelegate != address(0)) {
            _moveDelegatedPower(currentDelegate, delegatee, _getVotingPower(msg.sender));
        }
        
        _updateVotingPower(msg.sender);
        _updateVotingPower(delegatee);
    }

    // Internal functions
    function _getVotingPower(
        address account
    ) internal view returns (uint256) {
        VotingPower storage power = votingPower[account];
        
        uint256 tokenPower = votingToken.balanceOf(account);
        uint256 stakingPower = staking.getStakingPower(account);
        uint256 nftPower = _calculateNFTPower(account);
        
        return tokenPower + stakingPower + nftPower + power.delegatedPower;
    }

    function _moveDelegatedPower(
        address from,
        address to,
        uint256 amount
    ) internal {
        if (from != address(0)) {
            votingPower[from].delegatedPower -= amount;
        }
        if (to != address(0)) {
            votingPower[to].delegatedPower += amount;
        }
    }

    function _updateVotingPower(address account) internal {
        VotingPower storage power = votingPower[account];
        
        power.tokenPower = votingToken.balanceOf(account);
        power.stakingPower = staking.getStakingPower(account);
        power.nftPower = _calculateNFTPower(account);
        power.lastUpdate = block.timestamp;
        
        emit VotingPowerUpdated(account, _getVotingPower(account));
    }

    function _calculateNFTPower(
        address account
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
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

    function getVotingPower(
        address account
    ) external view returns (VotingPower memory) {
        return votingPower[account];
    }

    function getDelegate(
        address account
    ) external view returns (address) {
        return delegates[account];
    }
} 