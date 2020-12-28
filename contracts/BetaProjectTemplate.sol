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
    uint256 percent; // percent of token that would be transfered to project owner after phase succeeds
}

struct VotesRecord {
    mapping(address => VotingReceipt) receipts;
    uint256 for_votes;
    uint256 against_votes;
}

struct VotingPhase {
    uint256 start;
    uint256 end;
    uint256 percent;
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

contract BetaProjectTemplate is BaseProjectTemplate {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BLOCKS_PER_DAY = 6500;
    uint256 public constant REPLAN_NOTICE = 1;
    uint256 public constant REPLAN_VOTE_WINDOW = 3;
    uint256 public constant PHASE_KEEPALIVE = 3;
    uint256 public constant INSURANCE_WINDOW = 3;
    uint256 public constant AUDIT_WINDOW = 5;

    IERC20 public USDT_address;

    uint256 public constant FAILED_PHASE_MAX = 2;

    int256 public current_phase;
    uint256 public phase_replan_deadline;
    uint256 public repay_deadline;
    uint256 public profit_rate;
    uint256 public promised_repay;
    uint256 public failed_phase_count;
    uint256 public failed_replan_count;

    VotingPhase[] phases;
    ReplanVotes replan_votes;
    mapping(address => bool) who_can_replan;

    event ProjectPhaseChange(bytes32 project_id, uint256 phaseid);
    event ProjectPhaseFail(bytes32 project_id, uint256 phaseid);
    event ProjectAllPhasesDone(bytes32 project_id);
    event ProjectReplanVoting(bytes32 project_id);
    event ProjectReplanFailed(bytes32 project_id);
    event ProjectRepaying(bytes32 project_id);
    event ProjectReplanNotice(bytes32 project_id);
    event ProjectReplaned(bytes32 project_id);
    event ReplanVoteCast(address voter, bool support, uint256 votes);

    modifier projectJustCreated() {
        require(status == ProjectStatus.Created);
        _;
    }

    modifier requireReplanAuth() {
        require(
            who_can_replan[msg.sender] == true,
            "ProjectTemplate: no replan auth"
        );
        _;
    }

    constructor(
        bytes32 _pid,
        string memory _symbol,
        address _platform,
        address _usdt
    ) public BaseProjectTemplate(_pid, _platform, _symbol) {
        status = ProjectStatus.Created;
        current_phase = -1;
        USDT_address = IERC20(_usdt);
        decimals = 6;
    }

    function initialize(
        address _recv,
        uint256 _raise_start,
        uint256 _raise_end,
        uint256 _min,
        uint256 _max,
        uint256 _repay_deadline,
        uint256 _profit_rate,
        PhaseInfo[] memory _phases,
        address[] memory _replan_grants,
        uint256 _insurance_rate
    ) public onlyOwner projectJustCreated {
        require(_phases.length > 1, "ProjectTemplate: phase length");
        require(
            _phases[0].percent <= 80,
            "ProjectTemplate: first phase can't over 80 percent"
        );
        uint256 total_percent = 0;
        for (uint256 i = 0; i < _phases.length; i++) {
            total_percent = total_percent.add(_phases[i].percent);
            require(
                _phases[i].start < _phases[i].end,
                "ProjectTemplate: phase boundaries across"
            );
            if (i + 1 < _phases.length) {
                require(
                    _phases[i].end <= _phases[i + 1].start,
                    "ProjectTemplate: phase boundaries across"
                );
            }
            // first phase is set to success by default
            phases.push(
                VotingPhase({
                    start: _phases[i].start,
                    end: _phases[i].end,
                    percent: _phases[i].percent,
                    closed: false,
                    result: i == 0,
                    claimed: false,
                    processed: false,
                    votes: VotesRecord({for_votes: 0, against_votes: 0})
                })
            );
        }
        require(total_percent == 100, "ProjectTemplate: not 100 percent");

        fund_receiver = _recv;
        audit_end = block.number + (BLOCKS_PER_DAY * AUDIT_WINDOW) / 120;
        raise_start = _raise_start;
        raise_end = _raise_end;
        min_amount = _min;
        max_amount = _max;
        insurance_rate = _insurance_rate;
        insurance_deadline = _raise_end + INSURANCE_WINDOW * BLOCKS_PER_DAY;
        require(
            _raise_start >= audit_end,
            "ProjectTemplate: raise start before audit end"
        );
        require(
            insurance_deadline <= _phases[0].start,
            "ProjectTemplate: phase start before insurance deadline"
        );
        repay_deadline = _repay_deadline;
        profit_rate = _profit_rate;
        for (uint256 i = 0; i < _replan_grants.length; i++) {
            who_can_replan[_replan_grants[i]] = true;
        }

        status = ProjectStatus.Auditing;
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

    function set_fund_receiver(address recv) public onlyOwner {
        fund_receiver = recv;
    }

    function get_total_phase_number() public view returns (uint256) {
        return phases.length;
    }

    function get_phase_info(uint256 phase_id)
        public
        view
        returns (
            uint256,
            uint256,
            bool,
            bool,
            uint256
        )
    {
        require(
            phase_id >= 0 && phase_id < phases.length,
            "ProjectTemplate: phase doesn't exists"
        );
        VotingPhase storage vp = phases[phase_id];
        require(vp.start > 0, "ProjectTemplate: phase doesn't exists");

        return (vp.start, vp.end, vp.closed, vp.result, vp.votes.against_votes);
    }

    function get_replan_vote_info()
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            replan_votes.checkpoint,
            replan_votes.deadline,
            replan_votes.votes.for_votes,
            replan_votes.votes.against_votes
        );
    }

    function voted(
        address user,
        uint256 phase_id,
        bool replan
    ) public view returns (uint256, bool) {
        if (replan) {
            require(
                replan_votes.checkpoint != 0,
                "ProjectTemplate: no running replan vote"
            );
            VotingReceipt storage vr = replan_votes.votes.receipts[user];
            if (vr.votes > 0) {
                return (vr.votes, true);
            } else {
                return (0, false);
            }
        } else {
            VotingPhase storage vp = phases[phase_id];
            require(vp.start != 0, "ProjectTemplate: no running phase vote");
            VotingReceipt storage vr = vp.votes.receipts[user];
            if (vr.votes > 0) {
                return (vr.votes, true);
            } else {
                return (0, false);
            }
        }
    }

    function current_phase_status()
        public
        view
        returns (
            uint256 start,
            uint256 end,
            bool closed,
            bool result
        )
    {
        require(
            uint256(current_phase) > 0 && uint256(current_phase) < phases.length
        );
        VotingPhase storage vp = phases[uint256(current_phase)];
        return (vp.start, vp.end, vp.closed, vp.result);
    }

    function actual_project_status() public view returns (ProjectStatus) {
        bool again = false;
        ProjectStatus _status = status;
        do {
            again = false;
            if (_status == ProjectStatus.Auditing) {
                if (block.number >= audit_end) {
                    (_status, again) = (ProjectStatus.Failed, true);
                }
            } else if (_status == ProjectStatus.Audited) {
                if (block.number >= raise_start && block.number < raise_end) {
                    (_status, again) = (ProjectStatus.Raising, false);
                }
            } else if (_status == ProjectStatus.Raising) {
                if (block.number >= raise_end) {
                    if (
                        actual_raised >= min_amount &&
                        actual_raised <= max_amount
                    ) {
                        (_status, again) = (ProjectStatus.Succeeded, true);
                    } else {
                        (_status, again) = (ProjectStatus.Refunding, true);
                    }
                }
            } else if (
                _status == ProjectStatus.Refunding &&
                USDT_address.balanceOf(address(this)) == 0
            ) {
                _status = ProjectStatus.Failed;
                again = true;
            } else if (_status == ProjectStatus.Succeeded) {
                if (block.number > insurance_deadline) {
                    (_status, again) = (ProjectStatus.Refunding, true);
                }
            } else if (_status == ProjectStatus.InsurancePaid) {
                if (block.number >= phases[0].start) {
                    (_status, again) = (ProjectStatus.Rolling, true);
                }
            } else if (_status == ProjectStatus.ReplanNotice) {
                if (block.number >= replan_votes.checkpoint) {
                    (_status, again) = (ProjectStatus.ReplanVoting, true);
                }
            } else if (_status == ProjectStatus.PhaseFailed) {
                if (
                    phase_replan_deadline > 0 &&
                    block.number >= phase_replan_deadline
                ) {
                    (_status, again) = (ProjectStatus.Liquidating, true);
                } else if (
                    replan_votes.checkpoint > 0 &&
                    block.number >= replan_votes.checkpoint
                ) {
                    (_status, again) = (ProjectStatus.ReplanVoting, true);
                }
            } else if (_status == ProjectStatus.ReplanVoting) {
                if (block.number >= replan_votes.deadline) {
                    if (failed_replan_count + 1 >= 2) {
                        (_status, again) = (ProjectStatus.Liquidating, true);
                    } else {
                        (_status, again) = (ProjectStatus.ReplanFailed, true);
                    }
                }
            } else if (_status == ProjectStatus.ReplanFailed) {
                if (
                    failed_replan_count >= 2 ||
                    (phase_replan_deadline > 0 &&
                        block.number >= phase_replan_deadline)
                ) {
                    (_status, again) = (ProjectStatus.Liquidating, true);
                } else if (
                    replan_votes.checkpoint > 0 &&
                    block.number >= replan_votes.checkpoint
                ) {
                    (_status, again) = (ProjectStatus.ReplanVoting, true);
                }
            } else if (_status == ProjectStatus.Liquidating) {
                if (USDT_address.balanceOf(address(this)) == 0) {
                    _status = ProjectStatus.Failed;
                    again = true;
                }
            } else if (_status == ProjectStatus.AllPhasesDone) {
                if (
                    block.number < repay_deadline &&
                    USDT_address.balanceOf(address(this)) >= promised_repay
                ) {
                    _status = ProjectStatus.Repaying;
                    again = true;
                }
            } else if (_status == ProjectStatus.Repaying) {
                if (USDT_address.balanceOf(address(this)) == 0) {
                    (_status, again) = (ProjectStatus.Finished, true);
                }
            }
        } while (again);
        return _status;
    }

    function replan(PhaseInfo[] calldata _phases) public requireReplanAuth {
        uint256 total_percent_left;
        uint256 total_percent_new;
        if (status == ProjectStatus.Rolling) {
            require(
                current_phase >= 0 &&
                    uint256(current_phase) + 1 < phases.length &&
                    phases[uint256(current_phase)].closed &&
                    phases[uint256(current_phase)].result &&
                    block.number < phases[uint256(current_phase + 1)].start,
                "ProjectTemplate: not allowed to replan"
            );
            for (
                uint256 i = uint256(current_phase) + 1;
                i < phases.length;
                i++
            ) {
                total_percent_left = total_percent_left.add(phases[i].percent);
            }
            for (uint256 j = 0; j < _phases.length; j++) {
                total_percent_new = total_percent_new.add(_phases[j].percent);
            }
            require(
                total_percent_left == total_percent_new,
                "ProjectTemplate: inconsistent percent"
            );
            _replan(_phases);
        } else {
            require(
                status == ProjectStatus.PhaseFailed ||
                    status == ProjectStatus.ReplanFailed,
                "ProjectTemplate: not allowed to replan"
            );
            require(
                block.number < phase_replan_deadline,
                "ProjectTemplate: missing the replan window"
            );
            for (uint256 i = uint256(current_phase); i < phases.length; i++) {
                total_percent_left = total_percent_left.add(phases[i].percent);
            }
            for (uint256 j = 0; j < _phases.length; j++) {
                total_percent_new = total_percent_new.add(_phases[j].percent);
            }
            require(
                total_percent_left == total_percent_new,
                "ProjectTemplate: inconsistent percent"
            );
            _replan(_phases);
        }
    }

    function _replan(PhaseInfo[] memory _phases) internal {
        uint256 checkpoint = block.number + BLOCKS_PER_DAY * REPLAN_NOTICE;
        uint256 deadline = checkpoint + BLOCKS_PER_DAY * REPLAN_VOTE_WINDOW;
        require(
            _phases[0].start >= deadline,
            "ProjectTemplate: new phase start before replan vote"
        );
        _reset_replan_votes();
        for (uint256 i = 0; i < _phases.length; i++) {
            replan_votes.new_phases.push(
                VotingPhase({
                    start: _phases[i].start,
                    end: _phases[i].end,
                    percent: _phases[i].percent,
                    closed: false,
                    result: false,
                    claimed: false,
                    processed: false,
                    votes: VotesRecord({for_votes: 0, against_votes: 0})
                })
            );
        }
        replan_votes.checkpoint = checkpoint;
        replan_votes.deadline = deadline;
        phase_replan_deadline = 0;
        status = ProjectStatus.ReplanNotice;
        emit ProjectReplanNotice(id);
    }

    function _reset_replan_votes() internal {
        replan_votes.checkpoint = 0;
        replan_votes.deadline = 0;
        replan_votes.votes = VotesRecord({for_votes: 0, against_votes: 0});
        delete replan_votes.new_phases;
    }

    function _heartbeat_auditing() internal returns (bool) {
        if (block.number >= audit_end) {
            status = ProjectStatus.Failed;
            emit ProjectFailed(id);
            return true;
        }
        return false;
    }

    function _heartbeat_raising() internal returns (bool) {
        if (block.number >= raise_end) {
            if (actual_raised >= min_amount && actual_raised <= max_amount) {
                status = ProjectStatus.Succeeded;
                emit ProjectSucceeded(id);
                return true;
            } else {
                status = ProjectStatus.Refunding;
                emit ProjectRefunding(id);
                return true;
            }
        }
        return false;
    }

    function _heartbeat_succeeded() internal returns (bool) {
        if (block.number >= raise_end && promised_repay == 0) {
            uint256 money_utilize_blocks = repay_deadline - phases[0].start;
            uint256 year = 365 * BLOCKS_PER_DAY;
            uint256 interest =
                actual_raised
                    .mul(profit_rate)
                    .mul(money_utilize_blocks)
                    .div(10000)
                    .div(year);
            promised_repay = actual_raised.add(interest);
        }
        if (block.number > insurance_deadline) {
            status = ProjectStatus.Refunding;
            emit ProjectInsuranceFailure(id);
            emit ProjectRefunding(id);
            return true;
        }
        return false;
    }

    function _heartbeat_rolling() internal returns (bool) {
        bool again = false;

        VotingPhase storage current_vp = phases[uint256(current_phase)];
        if (
            !current_vp.processed &&
            !current_vp.closed &&
            block.number >= current_vp.end
        ) {
            // default pass
            _when_phase_been_passed(uint256(current_phase));
        }
        if (current_vp.closed && current_vp.result) {
            if (uint256(current_phase) < phases.length - 1) {
                int256 next_phase = current_phase + 1;
                VotingPhase storage next_vp = phases[uint256(next_phase)];
                if (block.number >= next_vp.start) {
                    current_phase = next_phase;
                    emit ProjectPhaseChange(id, uint256(current_phase));
                    again = true;
                }
            } else {
                if (block.number > current_vp.end) {
                    status = ProjectStatus.AllPhasesDone;
                    // move beyond valid phases
                    // easier to just claim all phases before current_phase
                    current_phase += 1;
                    emit ProjectAllPhasesDone(id);
                    again = true;
                }
            }
        }

        return again;
    }

    function _heartbeat_replannotice() internal returns (bool) {
        if (block.number >= replan_votes.checkpoint) {
            status = ProjectStatus.ReplanVoting;
            emit ProjectReplanVoting(id);
            return true;
        }
    }

    function _heartbeat_phasefailed() internal returns (bool) {
        if (
            phase_replan_deadline > 0 && block.number >= phase_replan_deadline
        ) {
            status = ProjectStatus.Liquidating;
            emit ProjectLiquidating(id);
            return true;
        } else if (
            replan_votes.checkpoint > 0 &&
            block.number >= replan_votes.checkpoint
        ) {
            status = ProjectStatus.ReplanVoting;
            emit ProjectReplanVoting(id);
            return true;
        }

        return false;
    }

    function _heartbeat_replanvoting() internal returns (bool) {
        if (block.number >= replan_votes.deadline) {
            failed_replan_count += 1;
            if (failed_replan_count >= 2) {
                status = ProjectStatus.Liquidating;
                emit ProjectLiquidating(id);
                return true;
            } else {
                status = ProjectStatus.ReplanFailed;
                _reset_replan_votes();
                phase_replan_deadline = _create_phase_replan_deadline();
                emit ProjectReplanFailed(id);
                return true;
            }
        }
        return false;
    }

    function _heartbeat_replanfailed() internal returns (bool) {
        if (
            failed_replan_count >= 2 ||
            (phase_replan_deadline > 0 && block.number >= phase_replan_deadline)
        ) {
            status = ProjectStatus.Liquidating;
            emit ProjectLiquidating(id);
            return true;
        } else if (
            replan_votes.checkpoint > 0 &&
            block.number >= replan_votes.checkpoint
        ) {
            status = ProjectStatus.ReplanVoting;
            emit ProjectReplanVoting(id);
            return true;
        }
        return false;
    }

    function _heartbeat_repaying() internal returns (bool) {
        if (USDT_address.balanceOf(address(this)) == 0) {
            status = ProjectStatus.Finished;
            emit ProjectFinished(id);
        }
        return false;
    }

    // it should be easier a hearbeat call only move a step forward but considering gas price,
    // one heartbeat may cause multiple moves to a temp steady status.
    function heartbeat() public override {
        bool again = false;
        do {
            again = false;

            if (status == ProjectStatus.Auditing) {
                again = _heartbeat_auditing();
            } else if (status == ProjectStatus.Audited) {
                if (block.number >= raise_start) {
                    status = ProjectStatus.Raising;
                    again = true;
                    emit ProjectRaising(id);
                }
            } else if (status == ProjectStatus.Raising) {
                again = _heartbeat_raising();
            } else if (
                status == ProjectStatus.Refunding &&
                USDT_address.balanceOf(address(this)) == 0
            ) {
                status = ProjectStatus.Failed;
                emit ProjectFailed(id);
                again = true;
            } else if (status == ProjectStatus.Succeeded) {
                again = _heartbeat_succeeded();
            } else if (status == ProjectStatus.InsurancePaid) {
                if (block.number >= phases[0].start) {
                    status = ProjectStatus.Rolling;
                    current_phase = 0;
                    emit ProjectRolling(id);
                    emit ProjectPhaseChange(id, uint256(current_phase));
                    again = true;
                }
            } else if (status == ProjectStatus.Rolling) {
                again = _heartbeat_rolling();
            } else if (status == ProjectStatus.ReplanNotice) {
                again = _heartbeat_replannotice();
            } else if (status == ProjectStatus.PhaseFailed) {
                again = _heartbeat_phasefailed();
            } else if (status == ProjectStatus.ReplanVoting) {
                again = _heartbeat_replanvoting();
            } else if (status == ProjectStatus.ReplanFailed) {
                again = _heartbeat_replanfailed();
            } else if (status == ProjectStatus.Liquidating) {
                if (USDT_address.balanceOf(address(this)) == 0) {
                    status = ProjectStatus.Failed;
                    emit ProjectFailed(id);
                    again = true;
                }
            } else if (status == ProjectStatus.AllPhasesDone) {
                if (
                    block.number < repay_deadline &&
                    USDT_address.balanceOf(address(this)) >= promised_repay
                ) {
                    status = ProjectStatus.Repaying;
                    emit ProjectRepaying(id);
                    again = true;
                }
            } else if (status == ProjectStatus.Repaying) {
                again = _heartbeat_repaying();
            }
        } while (again);
    }

    function platform_audit(bool pass, uint256 _insurance_rate)
        public
        override
        platformRequired
    {
        super.platform_audit(pass, _insurance_rate);
    }

    // only platform can recieve investment
    function platform_invest(address account, uint256 amount)
        public
        override
        platformRequired
        returns (uint256)
    {
        heartbeat();
        return super.platform_invest(account, amount);
    }

    function platform_refund(address account)
        public
        override
        platformRequired
        returns (uint256, uint256)
    {
        heartbeat();
        (uint256 amount, ) = super.platform_refund(account);
        USDT_address.safeTransfer(account, amount);
        return (amount, amount);
    }

    function platform_liquidate(address account)
        public
        override
        platformRequired
        returns (uint256, uint256)
    {
        heartbeat();
        (uint256 amount, ) = super.platform_liquidate(account);
        uint256 l_amount = _locked_investment().mul(amount).div(actual_raised);
        USDT_address.safeTransfer(account, l_amount);
        return (amount, l_amount);
    }

    function platform_repay(address account)
        public
        override
        platformRequired
        returns (uint256, uint256)
    {
        heartbeat();
        (uint256 amount, ) = super.platform_repay(account);
        uint256 profit_total = amount.mul(profit_rate).div(10000).add(amount);
        uint256 this_usdt_balance = USDT_address.balanceOf(address(this));
        require(this_usdt_balance > 0, "ProjectTemplate: no balance");
        if (profit_total > this_usdt_balance) {
            profit_total = this_usdt_balance;
        }
        USDT_address.safeTransfer(account, profit_total);
        return (amount, amount);
    }

    function vote_phase(uint256 phase_id, bool support) public {
        heartbeat();
        require(
            status == ProjectStatus.Rolling &&
                uint256(current_phase) == phase_id,
            "ProjectTemplate: can't vote this phase"
        );
        _cast_vote(msg.sender, phase_id, support);
        _check_vote_result();
    }

    function vote_against_phase(uint256 phase_id) public {
        vote_phase(phase_id, false);
    }

    function vote_replan(bool support) public {
        heartbeat();
        require(status == ProjectStatus.ReplanVoting);
        require(
            replan_votes.new_phases.length > 0,
            "ProjectTemplate: no replan auth"
        );
        require(
            block.number >= replan_votes.checkpoint &&
                block.number < replan_votes.deadline,
            "ProjectTemplate: replan vote window is over"
        );
        _cast_replan_vote(msg.sender, support);
        _check_replan_vote_result();
    }

    function vote_for_replan() public {
        vote_replan(true);
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
        heartbeat();
        // for (uint256 i = 0; i <= uint256(current_phase); i++) {
        //     VotingPhase storage vp = phases[i];
        //     require(vp.closed && vp.result, "ProjectTemplate: phase is wrong");
        //     if (vp.claimed) {
        //         continue;
        //     } else {
        //         vp.claimed = true;
        //         vp.processed = true;
        //         USDT_address.safeTransfer(
        //             fund_receiver,
        //             actual_raised.mul(vp.percent).div(100)
        //         );
        //     }
        // }
    }

    function _cast_vote(
        address voter,
        uint256 phase_id,
        bool support
    ) internal {
        require(
            uint256(current_phase) == phase_id,
            "ProjectTemplate: not current phase"
        );
        VotingPhase storage vp = phases[phase_id];
        require(!vp.closed, "ProjectTemplate: phase is closed");
        VotingReceipt storage receipt = vp.votes.receipts[voter];
        require(receipt.hasVoted == false, "ProjectTemplate: account voted");
        require(
            block.number >= vp.start,
            "ProjectTemplate: vote not start yet"
        );
        uint256 votes = getPriorVotes(voter, vp.start - 1);
        require(votes > 0, "ProjectTemplate: no votes");
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
        require(receipt.hasVoted == false, "ProjectTemplate: account voted");
        require(block.number >= replan_votes.checkpoint);
        uint256 votes = getPriorVotes(voter, replan_votes.checkpoint - 1);
        require(votes > 0, "ProjectTemplate: no votes");

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
            if (vp.votes.against_votes > actual_raised.div(2)) {
                _when_phase_been_denied(uint256(current_phase));
            } else if (block.number >= vp.end) {
                _when_phase_been_passed(uint256(current_phase));
            }
        }
    }

    // if replan vote gets passed, project status becomes Rolling
    // otherwise, ReplanFailed
    function _check_replan_vote_result() internal {
        uint256 polka = actual_raised.mul(2).div(3);
        if (replan_votes.votes.for_votes > polka) {
            // succeed
            failed_replan_count = 0;
            for (uint256 i = uint256(current_phase); i < phases.length; i++) {
                phases.pop();
            }
            for (uint256 i = 0; i < replan_votes.new_phases.length; i++) {
                phases.push(
                    VotingPhase({
                        start: replan_votes.new_phases[i].start,
                        end: replan_votes.new_phases[i].end,
                        percent: replan_votes.new_phases[i].percent,
                        closed: false,
                        result: false,
                        claimed: false,
                        processed: false,
                        votes: VotesRecord({for_votes: 0, against_votes: 0})
                    })
                );
            }
            _reset_replan_votes();
            status = ProjectStatus.Rolling;
        } else if (
            replan_votes.votes.against_votes >= actual_raised.sub(polka) ||
            block.number >= replan_votes.deadline
        ) {
            // fail
            failed_replan_count += 1;
            status = ProjectStatus.ReplanFailed;
            _reset_replan_votes();
        }
    }

    // _when_phase_been_passed should only be executed only once
    function _when_phase_been_passed(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(!vp.claimed && !vp.processed, "ProjectTemplate: phase error");
        vp.closed = true;
        vp.result = true;
        vp.claimed = true;
        vp.processed = true;
        USDT_address.safeTransfer(
            fund_receiver,
            actual_raised.mul(vp.percent).div(100)
        );
    }

    // _when_phase_been_denied should only be executed only once
    function _when_phase_been_denied(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(!vp.claimed && !vp.processed, "ProjectTemplate: phase error");
        vp.closed = true;
        vp.processed = true;
        failed_phase_count = failed_phase_count.add(1);
        if (failed_phase_count >= FAILED_PHASE_MAX) {
            status = ProjectStatus.Liquidating;
            emit ProjectLiquidating(id);
        } else {
            status = ProjectStatus.PhaseFailed;
            phase_replan_deadline = _create_phase_replan_deadline();
            emit ProjectPhaseFail(id, uint256(_phase_id));
        }
    }

    function _create_phase_replan_deadline() internal view returns (uint256) {
        return block.number + BLOCKS_PER_DAY * 3;
    }

    // function _beforeTokenTransfer(
    //     address from,
    //     address to,
    //     uint256 amount
    // ) internal virtual override {
    //     super._beforeTokenTransfer(from, to, amount);
    //     if (from == address(0)) {
    //         require(to == to);
    //         // When minting tokens
    //         uint256 newSupply = totalSupply.add(amount);
    //         require(newSupply <= max_amount);
    //     }
    // }

    function _locked_investment() internal view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = uint256(current_phase); i < phases.length; i++) {
            total = total.add(actual_raised.mul(phases[i].percent).div(100));
        }
        return total;
    }
}
