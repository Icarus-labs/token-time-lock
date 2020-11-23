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

    uint256 public actual_raised;
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

    function set_fund_receiver(address recv) public onlyOwner {
        fund_receiver = recv;
    }

    function voted(
        address user,
        uint256 phase_id,
        bool replan
    ) public view returns (uint256, bool) {
        if (replan) {
            require(replan_votes.checkpoint != 0);
            VotingReceipt storage vr = replan_votes.votes.receipts[user];
            if (vr.votes > 0) {
                return (vr.votes, true);
            } else {
                return (0, false);
            }
        } else {
            VotingPhase storage vp = phases[phase_id];
            require(vp.start != 0);
            VotingReceipt storage vr = vp.votes.receipts[user];
            if (vr.votes > 0) {
                return (vr.votes, true);
            } else {
                return (0, false);
            }
        }
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
        PhaseInfo[] memory _phases,
        address[] calldata _replan_grants
    ) public nonReentrant onlyOwner projectJustCreated {
        uint256 total_percent = 0;
        for (uint256 i = 0; i < _phases.length; i++) {
            total_percent = total_percent.add(_phases[i].percent);
            require(_phases[i].start < _phases[i].end);
            if (i + 1 < _phases.length) {
                require(_phases[i].end <= _phases[i + 1].start);
            }
            // first phase is set to success by default
            phases.push(
                VotingPhase({
                    start: _phases[i].start,
                    end: _phases[i].end,
                    percent: _phases[i].percent,
                    closed: i == 0,
                    result: i == 0,
                    claimed: false,
                    processed: false,
                    votes: VotesRecord({for_votes: 0, against_votes: 0})
                })
            );
        }
        require(total_percent == 100);
        fund_receiver = _recv;
        raise_start = _raise_start;
        raise_end = _raise_end;
        min_amount = _min;
        max_amount = _max;
        insurance_deadline = _insurance_deadline;
        repay_deadline = _repay_deadline;
        profit_rate = _profit_rate;
        status = ProjectStatus.Initialized;
        for (uint256 i = 0; i < _replan_grants.length; i++) {
            who_can_replan[_replan_grants[i]] = true;
        }
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
        uint256 total_percent_left;
        for (uint256 i = uint256(current_phase); i < phases.length; i++) {
            total_percent_left = total_percent_left.add(phases[i].percent);
        }
        uint256 total_percent_new;
        for (uint256 j = 0; j < _phases.length; j++) {
            total_percent_new = total_percent_new.add(_phases[j].percent);
        }
        require(total_percent_left == total_percent_new);
        uint256 checkpoint = block.number + BLOCKS_PER_DAY * REPLAN_NOTICE;
        uint256 deadline = checkpoint + BLOCKS_PER_DAY * REPLAN_VOTE_WINDOW;
        require(_phases[0].start >= deadline);
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
        if (block.number >= checkpoint) {
            status = ProjectStatus.ReplanVoting;
        }
    }

    function _reset_replan_votes() internal {
        replan_votes.checkpoint = 0;
        replan_votes.deadline = 0;
        replan_votes.votes = VotesRecord({for_votes: 0, against_votes: 0});
        delete replan_votes.new_phases;
    }

    function _heartbeat_initialized() internal {
        if (block.number >= raise_start && block.number < raise_end) {
            status = ProjectStatus.Collecting;
            emit ProjectCollecting(id);
        } else if (block.number >= raise_end) {
            status = ProjectStatus.Failed;
            emit ProjectFailed(id);
        }
    }

    function _heartbeat_collecting() internal {
        if (block.number >= raise_end) {
            if (actual_raised >= min_amount && actual_raised <= max_amount) {
                status = ProjectStatus.Succeeded;
                emit ProjectSucceeded(id);
            } else {
                status = ProjectStatus.Refunding;
                emit ProjectRefunding(id);
            }
        }
    }

    function _heartbeat_succeeded() internal {
        VotingPhase memory first_vp = phases[0];
        if (block.number >= raise_end && promised_repay == 0) {
            promised_repay = actual_raised.add(
                actual_raised.mul(profit_rate).div(10000)
            );
        }
        if (block.number > insurance_deadline && insurance_paid == false) {
            status = ProjectStatus.Refunding;
            emit ProjectInsuranceFailure(id);
            emit ProjectRefunding(id);
        } else if (block.number >= first_vp.start) {
            status = ProjectStatus.Rolling;
            current_phase = 0;
            emit ProjectRolling(id);
            emit ProjectPhaseChange(id, uint256(current_phase));
        }
    }

    function _heartbeat_rolling() internal {
        VotingPhase storage current_vp = phases[uint256(current_phase)];
        if (!current_vp.closed) {
            if (block.number >= current_vp.end) {
                _when_phase_been_passed(uint256(current_phase));
            }
        } else {
            if (!current_vp.result) {
                _when_phase_been_denied(uint256(current_phase));
            } else {
                if (uint256(current_phase) < phases.length - 1) {
                    int256 next_phase = current_phase + 1;
                    VotingPhase storage next_vp = phases[uint256(next_phase)];
                    if (block.number >= next_vp.start) {
                        current_phase = next_phase;
                        emit ProjectPhaseChange(id, uint256(current_phase));
                    }
                } else {
                    if (block.number > current_vp.end) {
                        status = ProjectStatus.AllPhasesDone;
                        // move beyond valid phases
                        // easier to just claim all phases before current_phase
                        current_phase += 1;
                        emit ProjectAllPhasesDone(id);
                    }
                }
            }
        }
    }

    function _heartbeat_phasefailed() internal {
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
    }

    function _heartbeat_replanvoting() internal {
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
    }

    function heartbeat() public override nonReentrant {
        if (status == ProjectStatus.Initialized) {
            _heartbeat_initialized();
        } else if (status == ProjectStatus.Collecting) {
            _heartbeat_collecting();
        } else if (
            status == ProjectStatus.Refunding &&
            USDT_address.balanceOf(address(this)) == 0
        ) {
            status = ProjectStatus.Failed;
            emit ProjectFailed(id);
        } else if (status == ProjectStatus.Succeeded) {
            _heartbeat_succeeded();
        } else if (status == ProjectStatus.Rolling) {
            _heartbeat_rolling();
        } else if (status == ProjectStatus.PhaseFailed) {
            _heartbeat_phasefailed();
        } else if (status == ProjectStatus.ReplanVoting) {
            _heartbeat_replanvoting();
        } else if (status == ProjectStatus.ReplanFailed) {
            if (
                failed_replan_count >= 2 ||
                block.number >= phase_replan_deadline
            ) {
                status = ProjectStatus.Liquidating;
                emit ProjectLiquidating(id);
            }
        } else if (status == ProjectStatus.Liquidating) {
            if (USDT_address.balanceOf(address(this)) == 0) {
                status = ProjectStatus.Failed;
                emit ProjectFailed(id);
            }
        } else if (status == ProjectStatus.AllPhasesDone) {
            if (
                block.number < repay_deadline &&
                USDT_address.balanceOf(address(this)) >= promised_repay
            ) {
                status = ProjectStatus.Repaying;
                emit ProjectRepaying(id);
            }
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
        require(max_amount > totalSupply);
        if (max_amount < totalSupply + amount) {
            amount = max_amount - totalSupply;
        }
        _mint(account, amount);
        actual_raised = actual_raised.add(amount);
    }

    function refund() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Refunding);
        uint256 amount = _balances[msg.sender];
        require(amount > 0);
        USDT_address.safeTransfer(msg.sender, amount);
        _transfer(msg.sender, address(this), amount);
    }

    function liquidate() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Liquidating);
        uint256 amount = _balances[msg.sender];
        require(amount > 0);
        uint256 l_amount = _locked_investment().mul(amount).div(actual_raised);
        USDT_address.safeTransfer(msg.sender, l_amount);
        _transfer(msg.sender, address(this), amount);
    }

    function repay() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.Repaying);
        uint256 amount = _balances[msg.sender];
        require(amount > 0);
        uint256 profit_total = amount.mul(profit_rate).div(10000).add(amount);
        uint256 this_usdt_balance = USDT_address.balanceOf(address(this));
        require(this_usdt_balance > 0);
        if (profit_total > this_usdt_balance) {
            profit_total = this_usdt_balance;
        }
        _transfer(msg.sender, address(this), amount);
        USDT_address.safeTransfer(msg.sender, profit_total);
    }

    function vote_against_phase(uint256 phase_id) public nonReentrant {
        heartbeat();
        require(
            status == ProjectStatus.Rolling &&
                uint256(current_phase) == phase_id
        );
        _cast_vote(msg.sender, phase_id, false);
        _check_vote_result();
    }

    function vote_for_replan() public nonReentrant {
        heartbeat();
        require(status == ProjectStatus.ReplanVoting);
        require(replan_votes.new_phases.length > 0);
        require(
            block.number >= replan_votes.checkpoint &&
                block.number < replan_votes.deadline
        );
        _cast_replan_vote(msg.sender, true);
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
        for (uint256 i = 0; i <= uint256(current_phase); i++) {
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
                USDT_address.safeTransfer(
                    recv_address,
                    actual_raised.mul(vp.percent).div(100)
                );
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
        require(!vp.claimed && !vp.processed);
        vp.closed = true;
        vp.result = true;
        vp.claimed = true;
        vp.processed = true;
        address receiver = owner();
        if (fund_receiver != address(0)) {
            receiver = fund_receiver;
        }
        USDT_address.safeTransfer(
            receiver,
            actual_raised.mul(vp.percent).div(100)
        );
    }

    // _when_phase_been_denied should only be executed only once
    function _when_phase_been_denied(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(!vp.claimed && !vp.processed);
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
            total = total.add(actual_raised.mul(phases[i].percent).div(100));
        }
        return total;
    }
}
