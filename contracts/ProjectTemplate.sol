// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "./BaseProjectTemplate.sol";
import "./ProjectToken.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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

struct VotingPhase {
    uint256 start;
    uint256 end;
    uint256 success_tally;
    uint256 amount;
    bool closed;
    bool result;
    bool claimed;
    bool processed;
    mapping(address => VotingReceipt) receipts;
    uint256 for_votes;
    uint256 against_votes;
}

contract ProjectTemplate is BaseProjectTemplate, ProjectToken {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 constant USDT_address = IERC20(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );

    uint256 public constant FAILED_PHASE_MAX = 2;

    uint256 public min_amount;
    uint256 public raise_start;
    uint256 public raise_end;
    uint256 public insurance_deadline;
    bool public insurance_paid;
    VotingPhase[] public phases;
    int256 public current_phase;
    uint256 public repay_deadline;
    uint256 public profit_rate;
    uint256 public promised_repay;

    VotingPhase[][] public failed_phases;

    uint256 public failed_phase_count;
    uint256 public failed_replan_count;

    address public fund_receiver;

    modifier platformRequired() {
        require(
            msg.sender == platform,
            "ProjectTemplate: only platform is allowed to call this"
        );
        _;
    }

    modifier projectJustCreated() {
        require(
            status == ProjectStatus.Created,
            "ProjectTemplate: project has already been initialized"
        );
        _;
    }

    modifier projectStatusChange(ProjectStatus _to_status) {
        _;
        status = _to_status;
    }

    modifier projectInitialized() {
        require(
            status >= ProjectStatus.Initialized,
            "ProjectTemplate: project has not been initialized"
        );
        _;
    }

    event VoteCast(address who, uint256 phase_id, bool support, uint256 votes);

    constructor(address _platform, bytes32 id)
        public
        BaseProjectTemplate(id)
        ProjectToken("pjt")
    {
        platform = _platform;
        status = ProjectStatus.Created;
        current_phase = -1;
    }

    function set_fund_rceiver(address recv) public onlyOwner {
        fund_receiver = recv;
    }

    function init(
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

    function init(
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
    ) internal projectStatusChange(ProjectStatus.Initialized) {
        uint256 total_amount = 0;
        for (uint256 i = 0; i < _phases.length; i++) {
            total_amount = total_amount.add(_phases[i].amount);
            require(_phases[i].start < _phases[i].end);
            phases[i].start = _phases[i].start;
            phases[i].end = _phases[i].end;
            phases[i].amount = _phases[i].amount;
            phases[i].success_tally = _phases[i].success_tally;
        }
        require(
            total_amount >= _min && total_amount <= _max,
            "ProjectTemplate: inconsistant total phase amount and project raising amount"
        );
        raise_start = _raise_start;
        raise_end = _raise_end;
        min_amount = _min;
        max_amount = _max;
        insurance_deadline = _insurance_deadline;
        repay_deadline = _repay_deadline;
        profit_rate = _profit_rate;
    }

    function heartbeat() public projectInitialized {
        uint256 blocknumber = block.number;
        VotingPhase storage first_vp = phases[0];

        if (status == ProjectStatus.Initialized) {
            if (blocknumber >= raise_start && blocknumber <= raise_end) {
                status = ProjectStatus.Collecting;
                // emit ProjectCollecting()
            } else if (blocknumber > raise_end) {
                status = ProjectStatus.Failed;
                // emit ProjectFailed()
            }
            return;
        }

        if (status == ProjectStatus.Collecting) {
            if (totalSupply >= min_amount) {
                status = ProjectStatus.Succeeded;
                // emit ProjectSuccess
            } else if (blocknumber > raise_end) {
                status = ProjectStatus.Refunding;
                // emit ProjectRefunding
            }
            return;
        }

        if (
            status == ProjectStatus.Refunding &&
            USDT_address.balanceOf(address(this)) == 0
        ) {
            status = ProjectStatus.Failed;
            // emit ProjectFailed()
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
                // emit ProjectRefunding
                // emit ProjectInsuranceFailure
                return;
            }
            if (blocknumber >= first_vp.start) {
                status = ProjectStatus.Rolling;
                current_phase = 0;
                // emti ProjectRolling
                // emit ProjectPhaseChange
            }
            return;
        }

        if (status == ProjectStatus.Rolling) {
            VotingPhase storage current_vp = phases[uint256(current_phase)];
            if (!current_vp.closed) {
                if (blocknumber >= current_vp.end) {
                    status = ProjectStatus.PhaseFailed;
                    // emit ProjectPhaseFail
                    return;
                }
            } else {
                if (!current_vp.result) {
                    status = ProjectStatus.PhaseFailed;
                    // emit ProjectPhaseFail
                    // keep current_phase unchanged
                    return;
                } else {
                    if (uint256(current_phase) == phases.length - 1) {
                        if (blocknumber > current_vp.end) {
                            status = ProjectStatus.AllPhasesDone;
                            // move beyond valid phases
                            // easier to just claim all phases before current_phase
                            current_phase += 1;
                            // emit ProjectAllPhases
                            return;
                        }
                    } else if (uint256(current_phase) < phases.length - 1) {
                        int256 next_phase = current_phase + 1;
                        VotingPhase storage next_vp = phases[uint256(
                            next_phase
                        )];
                        if (blocknumber >= next_vp.start) {
                            current_phase = next_phase;
                            // emit ProjectPhaseNext
                            return;
                        }
                    }
                }
            }
        }

        if (status == ProjectStatus.AllPhasesDone) {
            if (
                blocknumber < repay_deadline &&
                USDT_address.balanceOf(address(this)) >= promised_repay
            ) {
                status = ProjectStatus.Finished;
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

        uint256 blocknumber = block.number;

        // collecting primary 3
        require(
            status == ProjectStatus.Collecting,
            "ProjectTemplate: project must be collecting"
        );
        require(
            blocknumber >= raise_start && blocknumber < raise_end,
            "ProjectTemplate: raising window is over"
        );
        require(
            max_amount >= totalSupply + amount,
            "ProjectTemplate: fully raised"
        );

        _mint(account, amount);
    }

    function platform_refund(address account)
        public
        override
        nonReentrant
        platformRequired
    {
        heartbeat();
        require(
            status == ProjectStatus.Refunding,
            "ProjectTemplate: project is not refunding"
        );
        _refund(account);
    }

    function refund() public nonReentrant {
        heartbeat();
        require(
            status == ProjectStatus.Refunding,
            "ProjectTemplate: project is not refunding"
        );
        _refund(msg.sender);
    }

    function _refund(address account) internal {
        uint256 amount = _balances[account];
        require(amount > 0, "ProjectTemplate: account doesn't hold any share");
        USDT_address.safeTransfer(account, amount);
        _transfer(account, address(this), amount);
    }

    function platform_repay(address account)
        public
        override
        nonReentrant
        platformRequired
    {
        heartbeat();
        require(
            status == ProjectStatus.Repaying,
            "ProjectTemplate: project is not repaying"
        );
        _repay(account);
    }

    function repay() public nonReentrant {
        heartbeat();
        require(
            status == ProjectStatus.Repaying,
            "ProjectTemplate: project is not repaying"
        );
        _repay(msg.sender);
    }

    function _repay(address account) internal {
        uint256 amount = _balances[account];
        require(amount > 0, "ProjectTemplate: account doesn't hold any share");
        uint256 profit_total = amount.mul(profit_rate).div(10000).add(amount);
        uint256 this_usdt_balance = USDT_address.balanceOf(address(this));
        require(this_usdt_balance > 0, "ProjectTemplate: insufficient USDT");
        if (profit_total > this_usdt_balance) {
            profit_total = this_usdt_balance;
        }
        _transfer(account, address(this), amount);
        USDT_address.safeTransfer(account, profit_total);
    }

    function cast_vote(uint256 phase_id, bool support) public {
        heartbeat();
        require(
            uint256(current_phase) == phase_id,
            "ProjectTemplate: voting is closed"
        );
        _cast_vote(msg.sender, phase_id, support);
        _check_vote_result();
    }

    // can be triggered by any one out there, many thanks to those keeping the project running
    function check_vote() public {
        heartbeat();
        _check_vote_result();
    }

    // owner can claim all phases that before current phase
    function claim() public onlyOwner {
        for (uint256 i = 0; i < uint256(current_phase); i++) {
            VotingPhase storage vp = phases[i];
            require(
                vp.closed && vp.result,
                "ProjectTemplate: voting phase is invalid to be claimed"
            );
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
        require(
            uint256(current_phase) == phase_id,
            "ProjectTemplate: voting is closed"
        );

        VotingPhase storage vp = phases[phase_id];
        require(!vp.closed, "ProjectTemplate: voting is closed");

        VotingReceipt storage receipt = vp.receipts[voter];
        require(
            receipt.hasVoted == false,
            "ProjectTemplate: voter already voted"
        );

        uint256 votes = getPriorVotes(voter, vp.start);

        if (support) {
            vp.for_votes = vp.for_votes.add(votes);
        } else {
            vp.against_votes = vp.against_votes.add(votes);
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, phase_id, support, votes);
    }

    // this can be triggered automatically or mannually
    function _check_vote_result() internal {
        VotingPhase storage vp = phases[uint256(current_phase)];
        if (!vp.closed) {
            if (vp.for_votes >= vp.success_tally) {
                vp.closed = true;
                vp.result = true;
                _whenPhaseBeenApproved(uint256(current_phase));
            } else if (vp.against_votes >= totalSupply.sub(vp.success_tally)) {
                vp.closed = true;
                vp.result = false;
                _whenPhaseBeenDenied(uint256(current_phase));
            }
        }
    }

    // _whenPhaseBeenApproved should only be executed only once
    function _whenPhaseBeenApproved(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(
            !vp.claimed && !vp.processed,
            "ProjectTemplate: phase has been processed"
        );
        vp.claimed = true;
        vp.processed = true;

        address receiver = owner();
        if (fund_receiver != address(0)) {
            receiver = fund_receiver;
        }
        USDT_address.safeTransfer(receiver, vp.amount);
    }

    // _whenPhaseBeenDenied should only be executed only once
    function _whenPhaseBeenDenied(uint256 _phase_id) internal {
        VotingPhase storage vp = phases[_phase_id];
        require(
            !vp.claimed && !vp.processed,
            "ProjectTemplate: phase has been processed"
        );
        vp.processed = true;
        failed_phase_count = failed_phase_count.add(1);
        if (failed_phase_count >= FAILED_PHASE_MAX) {
            _fail_project();
        }
    }

    // TODO: liquidating
    function _fail_project() internal {}

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
            require(
                newSupply <= max_amount,
                "ProjectTemplate: max amount exceeded"
            );
        }
    }
}
