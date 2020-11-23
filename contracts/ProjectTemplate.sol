// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "./BaseProjectTemplate.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

// Ballot receipt record for a voter
struct VotingReceipt {
    bool hasVoted; // notice Whether or not a vote has been cast
    bool support; //  Whether or not the voter supports the proposal
    uint256 votes; //  The number of votes the voter had, which were cast
}

struct PhaseInfo {
    uint256 start; // start block number
    uint256 end; // end block number
    uint256 success_tally; // votes that needed for success
    uint256 amount; // amount of token that would be transfered to project owner after phase succeeds
}

struct VotesRecord {
    mapping(address => VotingReceipt) receipts;
    uint256 for_votes;
    uint256 against_votes;
}

struct VotingPhase {
    uint256 start;
    uint256 end;
    uint256 success_tally;
    uint256 amount;
    bool closed;
    bool result;
    bool claimed;
    bool processed;
    VotesRecord votes;
}

struct ReplanVotes {
    VotingPhase[] new_phases;
    VotesRecord votes;
    uint256 checkpoint;
    uint256 deadline;
}

contract ProjectTemplate is BaseProjectTemplate {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BLOCKS_PER_DAY = 6525;
    uint256 public constant REPLAN_NOTICE = 1;
    uint256 public constant REPLAN_VOTE_WINDOW = 3;
    uint256 public constant PHASE_KEEPALIVE = 3;

    IERC20 constant USDT_address =
        IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    uint256 public constant FAILED_PHASE_MAX = 2;

    uint256 public min_amount;
    uint256 public raise_start;
    uint256 public raise_end;
    uint256 public insurance_deadline;
    bool public insurance_paid;
    int256 public current_phase;
    uint256 public phase_replan_deadline;
    uint256 public repay_deadline;
    uint256 public profit_rate;
    uint256 public promised_repay;
    address public fund_receiver;
    uint256 public failed_phase_count;
    uint256 public failed_replan_count;

    VotingPhase[] phases;
    ReplanVotes replan_votes;
    mapping(address => bool) who_can_replan;

    event ProjectCollecting(bytes32 project_id);
    event ProjectFailed(bytes32 project_id);
    event ProjectSucceeded(bytes32 project_id);
    event ProjectRefunding(bytes32 project_id);
    event ProjectInsuranceFailure(bytes32 project_id);
    event ProjectRolling(bytes32 project_id);
    event ProjectPhaseChange(bytes32 project_id, uint256 phaseid);
    event ProjectPhaseFail(bytes32 project_id, uint256 phaseid);
    event ProjectAllPhasesDone(bytes32 project_id);
    event ProjectLiquidating(bytes32 project_id);
    event ProjectReplanVoting(bytes32 project_id);
    event ProjectReplanFailed(bytes32 project_id);
    event ProjectRepaying(bytes32 project_id);
    event ProjectFinished(bytes32 project_id);

    event ReplanVoteCast(address voter, bool support, uint256 votes);

    modifier projectJustCreated() {
        require(status == ProjectStatus.Created);
        _;
    }

    modifier requireReplanAuth() {
        require(who_can_replan[msg.sender] == true);
        _;
    }

    constructor(
        address _platform,
        bytes32 id,
        string memory symbol
    ) public BaseProjectTemplate(id) ProjectToken(symbol) {
        platform = _platform;
        status = ProjectStatus.Created;
        current_phase = -1;
        who_can_replan[msg.sender] = true;
    }

    function transferOwnership(address a) public virtual override onlyOwner {
        super.transferOwnership(a);
        who_can_replan[a] = true;
    }

    function revoke_replan_auth(address a) public onlyOwner {
        who_can_replan[a] = false;
    }

    function grant_replan_auth(address a) public onlyOwner {
        who_can_replan[a] = true;
    }

    function set_fund_rceiver(address recv) public onlyOwner {
        fund_receiver = recv;
    }

    function initialize(
        address _recv,
        uint256 _raise_start,
        uint256 _raise_end,
        uint256 _min,
        uint256 _max,
        uint256 _insurance_deadline,
        uint256 _repay_deadline,
        uint256 _profit_rate,
        PhaseInfo[] memory _phases
    ) public nonReentrant onlyOwner projectJustCreated {
        fund_receiver = _recv;
        _init(
            _raise_start,
            _raise_end,
            _min,
            _max,
            _insurance_deadline,
            _repay_deadline,
            _profit_rate,
            _phases
        );
    }

    function initialize(
        uint256 _raise_start,
        uint256 _raise_end,
        uint256 _min,
        uint256 _max,
        uint256 _insurance_deadline,
        uint256 _repay_deadline,
        uint256 _profit_rate,
        PhaseInfo[] memory _phases
    ) public nonReentrant onlyOwner projectJustCreated {
        _init(
            _raise_start,
            _raise_end,
            _min,
            _max,
            _insurance_deadline,
            _repay_deadline,
            _profit_rate,
            _phases
        );
    }

    function _init(
        uint256 _raise_start,
        uint256 _raise_end,
        uint256 _min,
        uint256 _max,
        uint256 _insurance_deadline,
        uint256 _repay_deadline,
        uint256 _profit_rate,
        PhaseInfo[] memory _phases
    ) internal {
        uint256 total_amount = 0;
        for (uint256 i = 0; i < _phases.length; i++) {
            total_amount = total_amount.add(_phases[i].amount);
            require(_phases[i].start < _phases[i].end);
            phases.push(
                VotingPhase({
                    start: _phases[i].start,
                    end: _phases[i].end,
                    amount: _phases[i].amount,
                    success_tally: _phases[i].success_tally,
                    closed: false,
                    result: false,
                    claimed: false,
                    processed: false,
                    votes: VotesRecord({for_votes: 0, against_votes: 0})
                })
            );
        }
        require(total_amount >= _min && total_amount <= _max);
        raise_start = _raise_start;
        raise_end = _raise_end;
        min_amount = _min;
        max_amount = _max;
        insurance_deadline = _insurance_deadline;
        repay_deadline = _repay_deadline;
        profit_rate = _profit_rate;
        status = ProjectStatus.Initialized;
    }

    function replan(PhaseInfo[] calldata _phases)
        public
        requireReplanAuth
        nonReentrant
    {
        if (status == ProjectStatus.Rolling) {
            require(
                uint256(current_phase) + 1 < phases.length &&
                    phases[uint256(current_phase)].closed &&
                    phases[uint256(current_phase)].result &&
                    block.number < phases[uint256(current_phase + 1)].start
            );
            _replan(_phases);
        } else {
            require(
                status == ProjectStatus.PhaseFailed ||
                    status == ProjectStatus.ReplanFailed
            );
            _replan(_phases);
        }
    }

    function _replan(PhaseInfo[] memory _phases) internal {
        uint256 phase_left = phases.length - uint256(current_phase);
        require(_phases.length == phase_left);
        uint256 total_amount_left;
        for (uint256 i = uint256(current_phase); i < phases.length; i++) {
            total_amount_left = total_amount_left.add(phases[i].amount);
        }
        uint256 total_amount_new;
        for (uint256 j = 0; j < _phases.length; j++) {
            total_amount_new = total_amount_new.add(_phases[j].amount);
        }
        require(total_amount_left == total_amount_new);
        uint256 checkpoint = block.number + BLOCKS_PER_DAY * REPLAN_NOTICE;
        uint256 deadline = checkpoint + BLOCKS_PER_DAY * REPLAN_VOTE_WINDOW;
        require(_phases[0].start >= deadline);
        _setup_vote_for_replan(_phases, checkpoint, deadline);
    }

    function _reset_replan_votes() internal {
        replan_votes.checkpoint = 0;
        replan_votes.deadline = 0;
        replan_votes.votes = VotesRecord({for_votes: 0, against_votes: 0});
        delete replan_votes.new_phases;
    }

    function _setup_vote_for_replan(
        PhaseInfo[] memory _phases,
        uint256 checkpoint,
        uint256 deadline
    ) internal {
        _reset_replan_votes();
        for (uint256 i = 0; i < _phases.length; i++) {
            replan_votes.new_phases[i].start = _phases[i].start;
            replan_votes.new_phases[i].end = _phases[i].end;
            replan_votes.new_phases[i].amount = _phases[i].amount;
            replan_votes.new_phases[i].success_tally = _phases[i].success_tally;
        }
        replan_votes.checkpoint = checkpoint;
        replan_votes.deadline = deadline;
        if (block.number >= checkpoint) {
            status = ProjectStatus.ReplanVoting;
        }
    }

    function heartbeat() public override nonReentrant {
        uint256 blocknumber = block.number;
        VotingPhase storage first_vp = phases[0];

        if (status == ProjectStatus.Initialized) {
            if (blocknumber >= raise_start && blocknumber < raise_end) {
                status = ProjectStatus.Collecting;
                emit ProjectCollecting(id);
            } else if (blocknumber >= raise_end) {
                status = ProjectStatus.Failed;
                emit ProjectFailed(id);
            }
            return;
        }

        if (status == ProjectStatus.Collecting) {
            if (totalSupply >= min_amount) {
                status = ProjectStatus.Succeeded;
                emit ProjectSucceeded(id);
            } else if (blocknumber >= raise_end) {
                status = ProjectStatus.Refunding;
                emit ProjectRefunding(id);
            }
            return;
        }

        if (
            status == ProjectStatus.Refunding &&
            USDT_address.balanceOf(address(this)) == 0
        ) {
            status = ProjectStatus.Failed;
            emit ProjectFailed(id);
            return;
        }

        if (status == ProjectStatus.Succeeded) {
            if (blocknumber >= raise_end && promised_repay == 0) {
                promised_repay = totalSupply.add(
                    totalSupply.mul(profit_rate).div(10000)
                );
            }
            if (blocknumber > insurance_deadline && insurance_paid == false) {
                status = ProjectStatus.Refunding;
                emit ProjectInsuranceFailure(id);
                emit ProjectRefunding(id);
            } else if (blocknumber >= first_vp.start) {
                status = ProjectStatus.Rolling;
                current_phase = 0;
                emit ProjectRolling(id);
                emit ProjectPhaseChange(id, uint256(current_phase));
            }
            return;
        }

        if (status == ProjectStatus.Rolling) {
            VotingPhase storage current_vp = phases[uint256(current_phase)];
            if (!current_vp.closed) {
                if (blocknumber >= current_vp.end) {
                    _phase_fail(uint256(current_phase));
                    return;
                }
            } else {
                if (!current_vp.result) {
                    _phase_fail(uint256(current_phase));
                    return;
                } else {
                    if (uint256(current_phase) == phases.length - 1) {
                        if (blocknumber > current_vp.end) {
                            status = ProjectStatus.AllPhasesDone;
                            // move beyond valid phases
                            // easier to just claim all phases before current_phase
                            current_phase += 1;
                            emit ProjectAllPhasesDone(id);
                            return;
                        }
                    } else if (uint256(current_phase) < phases.length - 1) {
                        int256 next_phase = current_phase + 1;
                        VotingPhase storage next_vp =
                            phases[uint256(next_phase)];
                        if (blocknumber >= next_vp.start) {
                            current_phase = next_phase;
                            emit ProjectPhaseChange(id, uint256(current_phase));
                            return;
                        }
                    }
                }
            }
            return;
        }

        if (status == ProjectStatus.PhaseFailed) {
            if (block.number >= phase_replan_deadline) {
                status = ProjectStatus.Liquidating;
                emit ProjectLiquidating(id);
            } else if (
                replan_votes.checkpoint > 0 &&
                block.number >= replan_votes.checkpoint
            ) {
                status = ProjectStatus.ReplanVoting;
                emit ProjectReplanVoting(id);
            }
            return;
        }

        if (status == ProjectStatus.ReplanVoting) {
            if (block.number >= replan_votes.deadline) {
                failed_replan_count += 1;
                if (failed_replan_count >= 2) {
                    status = ProjectStatus.Liquidating;
                    emit ProjectLiquidating(id);
                } else {
                    status = ProjectStatus.ReplanFailed;
                    phase_replan_deadline = _create_phase_replan_deadline();
                    emit ProjectReplanFailed(id);
                }
            }
            return;
        }

        if (status == ProjectStatus.ReplanFailed) {
            if (
                failed_replan_count >= 2 ||
                block.number >= phase_replan_deadline
            ) {
                status = ProjectStatus.Liquidating;
                emit ProjectLiquidating(id);
            }
            return;
        }

        if (status == ProjectStatus.Liquidating) {
            if (USDT_address.balanceOf(address(this)) == 0) {
                status = ProjectStatus.Failed;
                emit ProjectFailed(id);
            }
            return;
        }

        if (status == ProjectStatus.AllPhasesDone) {
            if (
                blocknumber < repay_deadline &&
                USDT_address.balanceOf(address(this)) >= promised_repay
            ) {
                status = ProjectStatus.Repaying;
                emit ProjectRepaying(id);
            }
            return;
        }
    }

    // only platform can recieve investment
    function platform_invest(address account, uint256 amount)
        public
        override
        nonReentrant
        platformRequired
    {
        heartbeat();
        require(status == ProjectStatus.Collecting);
        require(max_amount >= totalSupply + amount);
        _mint(account, amount);
    }

    function refund() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Refunding);
        _refund(msg.sender);
    }

    function liquidate() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Liquidating);
        _liquidate(msg.sender);
    }

    function _refund(address account) internal {
        uint256 amount = _balances[account];
        require(amount > 0);
        USDT_address.safeTransfer(account, amount);
        _transfer(account, address(this), amount);
    }

    function _liquidate(address account) internal {
        uint256 amount = _balances[account];
        require(amount > 0);
        uint256 l_amount = _locked_investment().mul(amount).div(totalSupply);
        USDT_address.safeTransfer(account, l_amount);
        _transfer(account, address(this), amount);
    }

    function repay() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Repaying);
        _repay(msg.sender);
    }

    function _repay(address account) internal {
        uint256 amount = _balances[account];
        require(amount > 0);
        uint256 profit_total = amount.mul(profit_rate).div(10000).add(amount);
        uint256 this_usdt_balance = USDT_address.balanceOf(address(this));
        require(this_usdt_balance > 0);
        if (profit_total > this_usdt_balance) {
            profit_total = this_usdt_balance;
        }
        _transfer(account, address(this), amount);
        USDT_address.safeTransfer(account, profit_total);
    }

    function vote(uint256 phase_id, bool support) public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Rolling);
        require(uint256(current_phase) == phase_id);
        _cast_vote(msg.sender, phase_id, support);
        _check_vote_result();
    }

    function vote_replan(bool support) public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.ReplanVoting);
        require(replan_votes.new_phases.length > 0);
        require(
            block.number >= replan_votes.checkpoint &&
                block.number < replan_votes.deadline
        );
        _cast_replan_vote(msg.sender, support);
        _check_replan_vote_result();
    }

    // can be triggered by any one out there, many thanks to those keeping the project running
    function check_vote() public {
        if (status == ProjectStatus.Rolling) {
            _check_vote_result();
        } else if (status == ProjectStatus.ReplanVoting) {
            _check_replan_vote_result();
        }
        heartbeat();
    }

    // owner can claim all phases that before current phase
    function claim() public onlyOwner {
        for (uint256 i = 0; i < uint256(current_phase); i++) {
            VotingPhase storage vp = phases[i];
            require(vp.closed && vp.result);
            if (vp.claimed) {
                continue;
            } else {
                vp.claimed = true;
                vp.processed = true;
                address recv_address = msg.sender;
                if (fund_receiver != address(0)) {
                    recv_address = fund_receiver;
                }
                USDT_address.safeTransfer(recv_address, vp.amount);
            }
        }
    }

    function _cast_vote(
        address voter,
        uint256 phase_id,
        bool support
    ) internal {
        require(uint256(current_phase) == phase_id);

        VotingPhase storage vp = phases[phase_id];
        require(!vp.closed);

        VotingReceipt storage receipt = vp.votes.receipts[voter];
        require(receipt.hasVoted == false);

        uint256 votes = getPriorVotes(voter, vp.start);
        require(votes > 0);

        if (support) {
            vp.votes.for_votes = vp.votes.for_votes.add(votes);
        } else {
            vp.votes.against_votes = vp.votes.against_votes.add(votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, phase_id, support, votes);
    }

    function _cast_replan_vote(address voter, bool support) internal {
        VotingReceipt storage receipt = replan_votes.votes.receipts[voter];
        require(receipt.hasVoted == false);

        uint256 votes = getPriorVotes(voter, replan_votes.checkpoint);
        require(votes > 0);

        if (support) {
            replan_votes.votes.for_votes = replan_votes.votes.for_votes.add(
                votes
            );
        } else {
            replan_votes.votes.against_votes = replan_votes
                .votes
                .against_votes
                .add(votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit ReplanVoteCast(voter, support, votes);
    }

    // this can be triggered automatically or mannually
    function _check_vote_result() internal {
        VotingPhase storage vp = phases[uint256(current_phase)];
        if (!vp.closed) {
            if (vp.votes.for_votes >= vp.success_tally) {
                vp.closed = true;
                vp.result = true;
                _when_phase_been_approved(uint256(current_phase));
            } else if (
                vp.votes.against_votes >= totalSupply.sub(vp.success_tally)
            ) {
                vp.closed = true;
                vp.result = false;
                _when_phase_been_denied(uint256(current_phase));
            }
        }
    }

    // if replan vote gets passed, project status becomes Rolling
    // otherwise, ReplanFailed
    function _check_replan_vote_result() internal {
        uint256 polka = totalSupply.mul(2).div(3);
        if (replan_votes.votes.for_votes > polka) {
            // succeed
            failed_replan_count = 0;
            for (uint256 i = 0; i < replan_votes.new_phases.length; i++) {
                phases[uint256(current_phase) + i].start = replan_votes
                    .new_phases[i]
                    .start;
                phases[uint256(current_phase) + i].end = replan_votes
                    .new_phases[i]
                    .end;
                phases[uint256(current_phase) + i].amount = replan_votes
                    .new_phases[i]
                    .amount;
                phases[uint256(current_phase) + i].success_tally = replan_votes
                    .new_phases[i]
                    .success_tally;
                phases[uint256(current_phase) + i].closed = false;
                phases[uint256(current_phase) + i].result = false;
                phases[uint256(current_phase) + i].processed = false;
            }
            status = ProjectStatus.Rolling;
            _reset_replan_votes();
        } else if (replan_votes.votes.against_votes >= totalSupply.sub(polka)) {
            // fail
            failed_replan_count += 1;
            status = ProjectStatus.ReplanFailed;
            _reset_replan_votes();
        }
    }

    // _when_phase_been_approved should only be executed only once
    function _when_phase_been_approved(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(!vp.claimed && !vp.processed);
        vp.claimed = true;
        vp.processed = true;
        address receiver = owner();
        if (fund_receiver != address(0)) {
            receiver = fund_receiver;
        }
        USDT_address.safeTransfer(receiver, vp.amount);
    }

    // _when_phase_been_denied should only be executed only once
    function _when_phase_been_denied(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(!vp.claimed && !vp.processed);
        vp.processed = true;
        failed_phase_count = failed_phase_count.add(1);
        if (failed_phase_count >= FAILED_PHASE_MAX) {
            _project_fail();
        } else {
            _phase_fail(uint256(_phase_id));
        }
    }

    function _phase_fail(uint256 phase_id) internal {
        status = ProjectStatus.PhaseFailed;
        phase_replan_deadline = _create_phase_replan_deadline();
        emit ProjectPhaseFail(id, phase_id);
    }

    function _create_phase_replan_deadline() internal view returns (uint256) {
        return block.number + BLOCKS_PER_DAY * 3;
    }

    function _project_fail() internal {
        status = ProjectStatus.Liquidating;
        emit ProjectLiquidating(id);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (from == address(0)) {
            require(to == to);
            // When minting tokens
            uint256 newSupply = totalSupply.add(amount);
            require(newSupply <= max_amount);
        }
    }

    function _locked_investment() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = uint256(current_phase); i < phases.length; i++) {
            total = total.add(phases[i].amount);
        }
        return total;
    }
}
