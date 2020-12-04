// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";

contract MiningCommittee {
    using SafeMath for uint256;

    // @notice The name of this contract
    string public constant name = "MiningCommittee";
    uint256 public constant max_operations = 10;

    address public guardian;
    uint256 public total_voting_power;

    mapping(address => uint256) public members;
    mapping(address => bool) public supervised;

    // @notice The number of votes in support of a proposal required in order for a quorum to be reached and for a vote to succeed
    function quorum_votes(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].quorumVotes;
    }

    function voting_period(uint256 proposalId) public view returns (uint256) {
        return proposals[proposalId].votingPeriod;
    }

    // @notice The total number of proposals
    uint256 public proposalCount;

    struct Proposal {
        // @notice Unique id for looking up a proposal
        uint256 id;
        // @notice Creator of the proposal
        address proposer;
        // @notice the ordered list of target addresses for calls to be made
        address[] targets;
        // @notice The ordered list of values (i.e. msg.value) to be passed to the calls to be made
        uint256[] values;
        // @notice The ordered list of function signatures to be called
        string[] signatures;
        // @notice The ordered list of calldata to be passed to each call
        bytes[] calldatas;
        // @notice The block at which voting begins: holders must delegate their votes prior to this block
        uint256 startBlock;
        // @notice The block at which voting ends: votes must be cast prior to this block
        uint256 endBlock;
        // @notice Current number of votes in favor of this proposal
        uint256 forVotes;
        // @notice Current number of votes in opposition to this proposal
        uint256 againstVotes;
        // @notice Flag marking whether the proposal has been canceled
        bool canceled;
        // @notice Flag marking whether the proposal has been executed
        bool executed;
        uint256 votingPeriod;
        uint256 quorumVotes;
        // @notice Receipts of ballots for the entire set of voters
        mapping(address => Receipt) receipts;
    }

    // @notice Ballot receipt record for a voter
    struct Receipt {
        // @notice Whether or not a vote has been cast
        bool hasVoted;
        // @notice Whether or not the voter supports the proposal
        bool support;
        // @notice The number of votes the voter had, which were cast
        uint256 votes;
    }

    // @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    // @notice The official record of all proposals ever proposed
    mapping(uint256 => Proposal) public proposals;

    uint256[] public liveProposalIds;

    // @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    // @notice The EIP-712 typehash for the ballot struct used by the contract
    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(uint256 proposalId,bool support)");

    // @notice An event emitted when a new proposal is created
    event ProposalCreated(uint256 id, address proposer);

    // @notice An event emitted when a vote has been cast on a proposal
    event VoteCast(
        address voter,
        uint256 proposalId,
        bool support,
        uint256 votes
    );

    // @notice An event emitted when a proposal has been canceled
    event ProposalCanceled(uint256 id);

    // @notice An event emitted when a proposal has been queued in the Timelock
    event ProposalQueued(uint256 id, uint256 eta);

    // @notice An event emitted when a proposal has been executed in the Timelock
    event ProposalExecuted(uint256 id);

    modifier onlyGuardianOrCommittee() {
        if (guardian != address(0)) {
            require(msg.sender == guardian, "MiningCommittee: guardian only");
        } else {
            require(
                msg.sender == address(this),
                "MiningCommittee: committee only"
            );
        }
        _;
    }

    modifier validProposalOrigin() {
        require(
            msg.sender == guardian || supervised[msg.sender],
            "MiningCommittee: not valid proposal origin"
        );
        _;
    }

    constructor() public {
        guardian = msg.sender;
        total_voting_power = 0;
        supervised[address(this)] = true;
    }

    function abdicate() public {
        require(msg.sender == guardian, "MiningCommittee: guardian only");
        guardian = address(0);
    }

    function update_member(address addr, uint256 votes)
        public
        onlyGuardianOrCommittee
    {
        if (votes > 0) {
            members[addr] = votes;
            total_voting_power = total_voting_power.add(votes);
        } else {
            total_voting_power = total_voting_power.sub(members[addr]);
            delete members[addr];
        }
    }

    function update_supervised(address addr, bool valid)
        public
        onlyGuardianOrCommittee
    {
        if (valid) {
            supervised[addr] = true;
        } else {
            delete supervised[addr];
        }
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        uint256 start,
        uint256 end
    ) public validProposalOrigin returns (uint256) {
        require(
            targets.length == values.length &&
                targets.length == signatures.length &&
                targets.length == calldatas.length,
            "MiningCommittee: proposal function information arity mismatch"
        );
        require(targets.length != 0, "MiningCommittee: must provide actions");
        require(
            targets.length <= max_operations,
            "MiningCommittee: too many actions"
        );

        uint256 votingPeriod = end - start;
        uint256 quorumVotes = total_voting_power.div(2);
        if (quorumVotes.mul(2) < total_voting_power) {
            quorumVotes += 1;
        }

        proposalCount++;
        Proposal memory newProposal =
            Proposal({
                id: proposalCount,
                proposer: msg.sender,
                targets: targets,
                values: values,
                signatures: signatures,
                calldatas: calldatas,
                startBlock: start,
                endBlock: end,
                forVotes: 0,
                againstVotes: 0,
                canceled: false,
                executed: false,
                votingPeriod: votingPeriod,
                quorumVotes: quorumVotes
            });

        proposals[newProposal.id] = newProposal;

        emit ProposalCreated(newProposal.id, msg.sender);
        return newProposal.id;
    }

    function execute(uint256 proposalId) internal {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "MiningCommittee: proposal can only be executed if it is succeeded"
        );
        Proposal storage proposal = proposals[proposalId];
        require(proposal.executed == false, "MiningCommittee: re-execute");
        proposal.executed = true;
        for (uint256 i = 0; i < proposal.targets.length; i++) {
            bytes memory callData;
            if (bytes(proposal.signatures[i]).length == 0) {
                callData = proposal.calldatas[i];
            } else {
                callData = abi.encodePacked(
                    bytes4(keccak256(bytes(proposal.signatures[i]))),
                    proposal.calldatas[i]
                );
            }
            // solium-disable-next-line security/no-call-value
            (bool success, ) =
                proposal.targets[i].call{value: proposal.values[i]}(callData);
            require(
                success,
                "MiningCommittee: Transaction execution reverted."
            );
        }
        emit ProposalExecuted(proposalId);
    }

    // function cancel(uint256 proposalId) public {
    //     ProposalState state = state(proposalId);
    //     require(
    //         state != ProposalState.Executed,
    //         "MiningCommittee: cannot cancel executed proposal"
    //     );

    //     Proposal storage proposal = proposals[proposalId];
    //     require(
    //         msg.sender == guardian ||
    //             proposal.proposer == msg.sender ||
    //             token.getPriorVotes(
    //                 proposal.proposer,
    //                 sub256(block.number, 1)
    //             ) <
    //             proposalThreshold(),
    //         "MiningCommittee: proposer above threshold"
    //     );

    //     proposal.canceled = true;
    //     for (uint256 i = 0; i < proposal.targets.length; i++) {
    //         timelock.cancelTransaction(
    //             proposal.targets[i],
    //             proposal.values[i],
    //             proposal.signatures[i],
    //             proposal.calldatas[i],
    //             proposal.eta
    //         );
    //     }

    //     emit ProposalCanceled(proposalId);
    // }

    function get_actions(uint256 proposalId)
        public
        view
        returns (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        )
    {
        Proposal storage p = proposals[proposalId];
        return (p.targets, p.values, p.signatures, p.calldatas);
    }

    function get_receipt(uint256 proposalId, address voter)
        public
        view
        returns (Receipt memory)
    {
        return proposals[proposalId].receipts[voter];
    }

    function state(uint256 proposalId) public view returns (ProposalState) {
        require(
            proposalCount >= proposalId && proposalId > 0,
            "MiningCommittee: invalid proposal id"
        );
        Proposal storage proposal = proposals[proposalId];
        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            if (proposal.forVotes >= quorum_votes(proposalId)) {
                return ProposalState.Succeeded;
            } else {
                return ProposalState.Active;
            }
        } else if (
            proposal.forVotes <= proposal.againstVotes ||
            proposal.forVotes < quorum_votes(proposalId)
        ) {
            return ProposalState.Defeated;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else {
            return ProposalState.Pending;
        }
    }

    function vote(uint256 proposalId, bool support) public {
        _castVote(msg.sender, proposalId, support);
    }

    function vote_by_sig(
        uint256 proposalId,
        bool support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator =
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes(name)),
                    chain_id(),
                    address(this)
                )
            );
        bytes32 structHash =
            keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest =
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );
        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "MiningCommittee: invalid signature");
        return _castVote(signatory, proposalId, support);
    }

    function _castVote(
        address voter,
        uint256 proposalId,
        bool support
    ) internal {
        require(
            state(proposalId) == ProposalState.Active,
            "MiningCommittee: voting is closed"
        );
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(
            receipt.hasVoted == false,
            "MiningCommittee: voter already voted"
        );
        uint256 votes = members[voter];
        if (support) {
            proposal.forVotes = proposal.forVotes.add(votes);
        } else {
            proposal.againstVotes = proposal.againstVotes.add(votes);
        }
        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;
        emit VoteCast(voter, proposalId, support, votes);
        if (state(proposalId) == ProposalState.Succeeded) {
            execute(proposalId);
        }
    }

    function chain_id() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
