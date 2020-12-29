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

struct VotesRecord {
    mapping(address => VotingReceipt) receipts;
    uint256 for_votes;
    uint256 against_votes;
}

struct Proposal {
    uint256 amount;
    string desc;
    uint256 start;
    uint256 end;
    address owner;
    bool finished;
    bool result;
}

contract MoneyDaoTemplate is BaseProjectTemplate {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BLOCKS_PER_DAY = 6500;
    uint256 public constant INSURANCE_WINDOW = 3;
    uint256 public constant AUDIT_WINDOW = 5;

    IERC20 public USDT_address;

    uint256 public repay_deadline;
    uint256 public profit_rate;
    uint256 public promised_repay;
    uint256 public active_proposal;

    mapping(address => bool) public proposers;

    Proposal[] public proposals;
    VotesRecord[] public votes_records;
    mapping(address => uint256[]) public user_proposals;

    modifier projectJustCreated() {
        require(status == ProjectStatus.Created);
        _;
    }

    modifier onlyProposers() {
        require(proposers[msg.sender], "MoneyDaoTemplate: only proposer");
        _;
    }

    event ProposalPassed(bytes32 projectid, uint256 proposalid);
    event ProposalDenied(bytes32 projectid, uint256 proposalid);
    event MoneyGiven(bytes32 projectid, uint256 amount);

    constructor(
        bytes32 _pid,
        string memory _symbol,
        address _platform,
        address _usdt
    ) public BaseProjectTemplate(_pid, _platform, _symbol) {
        status = ProjectStatus.Created;
        USDT_address = IERC20(_usdt);
        decimals = 6;
        proposers[msg.sender] = true;
    }

    function update_proposer(address np, bool y) public onlyOwner {
        require(np != address(0));
        proposers[np] = y;
    }

    function initialize(
        address _recv,
        uint256 _raise_span,
        uint256 _min,
        uint256 _max,
        uint256 _repay_deadline,
        uint256 _profit_rate,
        uint256 _insurance_rate
    ) public onlyOwner projectJustCreated {
        fund_receiver = _recv;
        audit_end = block.number + BLOCKS_PER_DAY * AUDIT_WINDOW;
        raise_end = block.number + _raise_span;
        min_amount = _min;
        max_amount = _max;
        insurance_deadline =
            block.number +
            _raise_span +
            INSURANCE_WINDOW *
            BLOCKS_PER_DAY;
        repay_deadline = _repay_deadline;
        require(
            repay_deadline > insurance_deadline,
            "MoneyDaoTemplate: repay deadline too early"
        );
        profit_rate = _profit_rate;
        status = ProjectStatus.Auditing;
        insurance_rate = _insurance_rate;
    }

    function set_fund_receiver(address recv) public onlyOwner {
        fund_receiver = recv;
    }

    function voted(address user, uint256 proposal_id)
        public
        view
        returns (
            uint256 _votes,
            bool _yesorno,
            bool _voted
        )
    {
        VotesRecord storage vr = votes_records[proposal_id];
        require(
            vr.for_votes > 0 || vr.against_votes > 0,
            "MoneyDaoTemplate: invalid proposal id"
        );
        return (
            vr.receipts[user].votes,
            vr.receipts[user].support,
            vr.receipts[user].hasVoted
        );
    }

    function next_proposal_id() public view returns (uint256) {
        return proposals.length;
    }

    function create_proposal(
        uint256 _proposal_id,
        string calldata _desc,
        uint256 _amount,
        uint256 _start,
        uint256 _end
    ) public onlyProposers returns (uint256) {
        require(
            status == ProjectStatus.Rolling,
            "MoneyDaoTemplate: project is not rolling"
        );
        require(
            proposals.length == 0 || active_proposal - proposals.length > 1,
            "MoneyDaoTemplate: only one active proposal is allowed"
        );
        require(
            _proposal_id == proposals.length,
            "MoneyDaoTemplate: invalid proposal id"
        );
        require(
            _amount <= USDT_address.balanceOf(address(this)),
            "MoneyDaoTemplate: not enough fund"
        );

        Proposal memory p =
            Proposal({
                amount: _amount,
                start: _start,
                end: _end,
                desc: _desc,
                owner: msg.sender,
                finished: false,
                result: false
            });
        proposals.push(p);
        VotesRecord memory vr = VotesRecord({for_votes: 0, against_votes: 0});
        votes_records.push(vr);
        user_proposals[msg.sender].push(_proposal_id);
        active_proposal = _proposal_id;

        require(
            proposals.length == votes_records.length,
            "MoneyDaoTemplate: inconsistent proposals against votes_records"
        );
        return _proposal_id;
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
                if (block.number < raise_end) {
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
                (_status, again) = (ProjectStatus.Rolling, true);
            } else if (_status == ProjectStatus.Liquidating) {
                if (USDT_address.balanceOf(address(this)) == 0) {
                    _status = ProjectStatus.Failed;
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
            uint256 money_utilize_blocks = repay_deadline - raise_end;
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

    function _heartbeat_rolling() internal returns (bool _again) {
        require(proposals.length > 0);
        Proposal storage psl = proposals[active_proposal];
        if (psl.finished == false && block.number >= psl.end) {
            _again = true;
            psl.finished = true;
            _remove_active_proposal();
            return _again;
        }
        return _again;
    }

    function _heartbeat_repaying() internal returns (bool) {
        if (USDT_address.balanceOf(address(this)) == 0) {
            status = ProjectStatus.Finished;
            emit ProjectFinished(id);
        }
        return false;
    }

    function fill_repay_tokens(uint256 amount) public {
        require(
            USDT_address.allowance(msg.sender, address(this)) >= amount,
            "MoneyDaoTemplate: USDT allowance not enough"
        );
        require(
            promised_repay <= USDT_address.balanceOf(address(this)).add(amount)
        );
        USDT_address.safeTransferFrom(msg.sender, address(this), amount);
        status = ProjectStatus.Repaying;
        emit ProjectRepaying(id);
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
                if (block.number < raise_end) {
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
                status = ProjectStatus.Rolling;
                emit ProjectRolling(id);
                again = true;
            } else if (status == ProjectStatus.Rolling) {
                if (proposals.length - 1 == active_proposal) {
                    again = _heartbeat_rolling();
                }
            } else if (status == ProjectStatus.Liquidating) {
                if (USDT_address.balanceOf(address(this)) == 0) {
                    status = ProjectStatus.Failed;
                    emit ProjectFailed(id);
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
        heartbeat();
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
        uint256 amount_left = USDT_address.balanceOf(address(this));
        uint256 l_amount = amount_left.mul(amount).div(actual_raised);
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
        require(this_usdt_balance > 0, "MoneyDaoTemplate: no balance");
        if (profit_total > this_usdt_balance) {
            profit_total = this_usdt_balance;
        }
        USDT_address.safeTransfer(account, profit_total);
        return (amount, amount);
    }

    function vote(bool support) public {
        heartbeat();
        Proposal storage p = proposals[active_proposal];
        require(
            block.number >= p.start && block.number < p.end,
            "MoneyDaoTemplate: proposal timing wrong"
        );
        require(
            status == ProjectStatus.Rolling &&
                p.amount > 0 &&
                p.finished == false,
            "MoneyDaoTemplate: proposal not valid"
        );
        _cast_vote(msg.sender, support);
        _check_vote_result();
    }

    // can be triggered by any one out there, many thanks to those keeping the project running
    function check_vote() public {
        require(
            status == ProjectStatus.Rolling &&
                proposals[active_proposal].amount > 0 &&
                proposals[active_proposal].finished == false,
            "MoneyDaoTemplate: proposal not valid"
        );
        _check_vote_result();
        heartbeat();
    }

    function _cast_vote(address voter, bool support) internal {
        Proposal storage psl = proposals[active_proposal];
        VotesRecord storage vr = votes_records[active_proposal];
        require(
            vr.receipts[voter].hasVoted == false,
            "MoneyDaoTemplate: account voted"
        );
        require(
            block.number >= psl.start && block.number < psl.end,
            "MoneyDaoTemplate: not in proposal vote window"
        );
        uint256 votes = getPriorVotes(voter, psl.start - 1);
        require(votes > 0, "MoneyDaoTemplate: no votes");
        if (support) {
            vr.for_votes = vr.for_votes.add(votes);
        } else {
            vr.against_votes = vr.against_votes.add(votes);
        }
        vr.receipts[voter].hasVoted = true;
        vr.receipts[voter].support = support;
        vr.receipts[voter].votes = votes;

        emit VoteCast(voter, active_proposal, support, votes);
    }

    function _check_vote_result() internal {
        VotesRecord storage vr = votes_records[active_proposal];
        if (vr.for_votes.mul(3) > totalSupply.mul(2)) {
            _passed();
        } else if (vr.against_votes.mul(3) >= totalSupply) {
            _denied();
        }
    }

    function _passed() internal {
        Proposal storage psl = proposals[active_proposal];
        USDT_address.safeTransfer(fund_receiver, psl.amount);
        psl.finished = true;
        psl.result = true;
        emit ProposalPassed(id, active_proposal);
        emit MoneyGiven(id, psl.amount);

        _remove_active_proposal();
    }

    function _denied() internal {
        Proposal storage psl = proposals[active_proposal];
        psl.finished = true;
        psl.result = false;
        emit ProposalDenied(id, active_proposal);

        _remove_active_proposal();
    }

    function _remove_active_proposal() internal {
        active_proposal = proposals.length + 99;
    }
}
