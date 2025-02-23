// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IIkigaiVaultV2.sol";
import "../interfaces/IIkigaiStakingV2.sol";

contract IkigaiGovernanceExtensionsV2 is AccessControl, ReentrancyGuard, Pausable {
    bytes32 public constant GOVERNANCE_MANAGER = keccak256("GOVERNANCE_MANAGER");
    bytes32 public constant PROPOSAL_CREATOR = keccak256("PROPOSAL_CREATOR");

    struct Proposal {
        address proposer;          // Proposal creator
        string description;        // Proposal description
        bytes[] actions;          // Actions to execute
        uint256 startTime;        // Voting start time
        uint256 endTime;          // Voting end time
        uint256 forVotes;         // Votes in favor
        uint256 againstVotes;     // Votes against
        uint256 quorum;           // Required quorum
        bool executed;            // Whether executed
        bool canceled;            // Whether canceled
    }

    struct Vote {
        bool support;             // Whether in favor
        uint256 power;           // Voting power
        uint256 timestamp;        // Vote timestamp
        string reason;           // Vote reason
    }

    struct VotingPower {
        uint256 tokenPower;       // Power from tokens
        uint256 stakingPower;     // Power from staking
        uint256 nftPower;         // Power from NFTs
        uint256 lastUpdate;       // Last update time
        uint256 lockEndTime;      // Power lock end time
    }

    // State variables
    IERC20 public immutable ikigaiToken;
    IIkigaiVaultV2 public vault;
    IIkigaiStakingV2 public staking;
    
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Vote)) public votes;
    mapping(address => VotingPower) public votingPower;
    mapping(address => uint256) public proposalNonce;
    
    uint256 public proposalCount;
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 100000 * 1e18; // 100k tokens
    uint256 public constant MIN_VOTING_PERIOD = 3 days;
    uint256 public constant MAX_VOTING_PERIOD = 14 days;
    
    // Events
    event ProposalCreated(uint256 indexed proposalId, address proposer);
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCanceled(uint256 indexed proposalId);

    constructor(
        address _ikigaiToken,
        address _vault,
        address _staking
    ) {
        ikigaiToken = IERC20(_ikigaiToken);
        vault = IIkigaiVaultV2(_vault);
        staking = IIkigaiStakingV2(_staking);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // Proposal management
    function createProposal(
        string calldata description,
        bytes[] calldata actions,
        uint256 votingPeriod
    ) external returns (uint256) {
        require(
            getVotingPower(msg.sender) >= MIN_PROPOSAL_THRESHOLD,
            "Insufficient power"
        );
        require(
            votingPeriod >= MIN_VOTING_PERIOD &&
            votingPeriod <= MAX_VOTING_PERIOD,
            "Invalid period"
        );
        
        uint256 proposalId = ++proposalCount;
        
        proposals[proposalId] = Proposal({
            proposer: msg.sender,
            description: description,
            actions: actions,
            startTime: block.timestamp,
            endTime: block.timestamp + votingPeriod,
            forVotes: 0,
            againstVotes: 0,
            quorum: _calculateQuorum(),
            executed: false,
            canceled: false
        });
        
        proposalNonce[msg.sender]++;
        
        emit ProposalCreated(proposalId, msg.sender);
        return proposalId;
    }

    // Voting
    function castVote(
        uint256 proposalId,
        bool support,
        string calldata reason
    ) external {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.executed && !proposal.canceled, "Proposal finalized");
        
        uint256 power = getVotingPower(msg.sender);
        require(power > 0, "No voting power");
        
        Vote storage vote = votes[proposalId][msg.sender];
        require(vote.timestamp == 0, "Already voted");
        
        // Record vote
        vote.support = support;
        vote.power = power;
        vote.timestamp = block.timestamp;
        vote.reason = reason;
        
        // Update totals
        if (support) {
            proposal.forVotes += power;
        } else {
            proposal.againstVotes += power;
        }
        
        emit VoteCast(proposalId, msg.sender, support);
    }

    // Proposal execution
    function executeProposal(
        uint256 proposalId
    ) external nonReentrant {
        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp > proposal.endTime, "Voting ongoing");
        require(!proposal.executed && !proposal.canceled, "Already finalized");
        require(
            proposal.forVotes + proposal.againstVotes >= proposal.quorum,
            "Quorum not reached"
        );
        require(
            proposal.forVotes > proposal.againstVotes,
            "Proposal rejected"
        );
        
        proposal.executed = true;
        
        // Execute actions
        for (uint256 i = 0; i < proposal.actions.length; i++) {
            _executeAction(proposal.actions[i]);
        }
        
        emit ProposalExecuted(proposalId);
    }

    // Voting power
    function getVotingPower(
        address account
    ) public view returns (uint256) {
        VotingPower storage power = votingPower[account];
        
        // Get token balance
        uint256 tokenPower = ikigaiToken.balanceOf(account);
        
        // Get staking power
        uint256 stakingPower = staking.getStakedBalance(account) * 2; // 2x multiplier
        
        // Get NFT power
        uint256 nftPower = _calculateNFTPower(account);
        
        return tokenPower + stakingPower + nftPower;
    }

    // Internal functions
    function _calculateQuorum() internal view returns (uint256) {
        return ikigaiToken.totalSupply() * 4 / 10; // 40% quorum
    }

    function _calculateNFTPower(
        address account
    ) internal view returns (uint256) {
        // Implementation needed
        return 0;
    }

    function _executeAction(bytes memory action) internal {
        // Implementation needed
    }

    // View functions
    function getProposal(
        uint256 proposalId
    ) external view returns (Proposal memory) {
        return proposals[proposalId];
    }

    function getVote(
        uint256 proposalId,
        address voter
    ) external view returns (Vote memory) {
        return votes[proposalId][voter];
    }

    function getVotingPowerBreakdown(
        address account
    ) external view returns (VotingPower memory) {
        return votingPower[account];
    }

    function getProposalCount(
        address proposer
    ) external view returns (uint256) {
        return proposalNonce[proposer];
    }
} 