// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

contract IkigaiGovernanceV2 is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    struct ProposalParameters {
        uint256 votingDelay;    // Delay before voting starts
        uint256 votingPeriod;   // Duration of voting
        uint256 quorumPercent;  // Required participation
        uint256 proposalThreshold; // Tokens needed to propose
    }

    // Emergency action types
    enum EmergencyAction {
        PAUSE_PROTOCOL,
        UNPAUSE_PROTOCOL,
        ADJUST_EMISSIONS,
        UPDATE_TREASURY,
        BLACKLIST_ADDRESS
    }

    event EmergencyActionProposed(
        EmergencyAction indexed actionType,
        address indexed proposer,
        uint256 proposalId
    );

    constructor(
        IVotes _token,
        TimelockController _timelock
    )
        Governor("IkigaiGovernance")
        GovernorSettings(
            1 days,     // 1 day voting delay
            7 days,     // 1 week voting period
            100_000 * 10**18  // 100k tokens needed to propose
        )
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(_timelock)
    {}

    // Emergency governance functions
    function proposeEmergencyAction(
        EmergencyAction actionType,
        address target,
        bytes memory calldataPayload
    ) external returns (uint256) {
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "GovernorV2: proposer votes below threshold"
        );

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Emergency Action Proposal";

        targets[0] = target;
        values[0] = 0;
        calldatas[0] = calldataPayload;

        uint256 proposalId = propose(targets, values, calldatas, description);

        emit EmergencyActionProposed(actionType, msg.sender, proposalId);

        return proposalId;
    }

    // Voting weight calculation with time-lock bonus
    function _getVotes(
        address account,
        uint256 blockNumber,
        bytes memory /*params*/
    ) internal view virtual override returns (uint256) {
        uint256 votes = super._getVotes(account, blockNumber, "");
        
        // Add bonus for long-term stakers (implemented in StakingV2)
        IStakingV2 staking = IStakingV2(stakingContract);
        uint256 stakingBonus = staking.getVotingPower(account);
        
        return votes + stakingBonus;
    }

    // The following functions are overrides required by Solidity

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) public override(Governor, IGovernor) returns (uint256) {
        return super.propose(targets, values, calldatas, description);
    }

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
} 