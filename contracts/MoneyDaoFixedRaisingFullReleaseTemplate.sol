// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "./BaseProjectTemplate.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract MoneyDaoFixedRaisingFullReleaseTemplate is BaseProjectTemplate {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BLOCKS_PER_DAY = 6500;
    uint256 public constant INSURANCE_WINDOW = 3;
    uint256 public constant AUDIT_WINDOW = 5;

    IERC20 public USDT_address;

    uint256 public repay_deadline;
    uint256 public profit_rate;
    uint256 public promised_repay;

    modifier projectJustCreated() {
        require(status == ProjectStatus.Created);
        _;
    }

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
    }

    function initialize(
        address _recv,
        uint256 _raise_start,
        uint256 _raise_end,
        uint256 _min,
        uint256 _max,
        uint256 _repay_deadline,
        uint256 _profit_rate,
        uint256 _insurance_rate
    ) public onlyOwner projectJustCreated {
        fund_receiver = _recv;
        audit_end = block.number + BLOCKS_PER_DAY * AUDIT_WINDOW;
        raise_start = _raise_start;
        raise_end = _raise_end;
        require(
            _raise_start >= audit_end,
            "MoneyDaoFixedRaisingFullReleaseTemplate: raise start before audit end"
        );
        min_amount = _min;
        max_amount = _max;
        insurance_deadline = _raise_end + INSURANCE_WINDOW * BLOCKS_PER_DAY;
        repay_deadline = _repay_deadline;
        require(
            repay_deadline > insurance_deadline,
            "MoneyDaoFixedRaisingFullReleaseTemplate: repay deadline too early"
        );
        profit_rate = _profit_rate;
        status = ProjectStatus.Auditing;
        insurance_rate = _insurance_rate;
    }

    function set_fund_receiver(address recv) public onlyOwner {
        fund_receiver = recv;
    }

    function mark_insurance_paid() public override platformRequired {
        require(
            block.number < insurance_deadline,
            "MoneyDaoFixedRaisingFullReleaseTemplate: missing the insurance window"
        );
        require(
            block.number >= raise_end,
            "MoneyDaoFixedRaisingFullReleaseTemplate: still in raising"
        );
        super.mark_insurance_paid();
        require(USDT_address.balanceOf(address(this)) >= actual_raised);
        USDT_address.safeTransfer(fund_receiver, actual_raised);
        emit MoneyGiven(id, actual_raised);

        heartbeat();
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
                if (block.number >= raise_start) {
                    (_status, again) = (ProjectStatus.Raising, true);
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
                if (balanceOf(address(this)) == totalSupply) {
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
        if (block.number > insurance_deadline) {
            status = ProjectStatus.Refunding;
            emit ProjectInsuranceFailure(id);
            emit ProjectRefunding(id);
            return true;
        }
        return false;
    }

    function _heartbeat_repaying() internal returns (bool) {
        if (balanceOf(address(this)) == totalSupply) {
            status = ProjectStatus.Finished;
            emit ProjectFinished(id);
        }
        return false;
    }

    function fill_repay_tokens(uint256 amount) public {
        require(
            USDT_address.allowance(msg.sender, address(this)) >= amount,
            "MoneyDaoFixedRaisingFullReleaseTemplate: USDT allowance not enough"
        );
        uint256 money_utilize_blocks;
        if (block.number <= repay_deadline) {
            money_utilize_blocks = repay_deadline.sub(raise_end);
        } else {
            money_utilize_blocks = block.number.sub(raise_end);
        }
        uint256 year = 365 * BLOCKS_PER_DAY;
        uint256 interest =
            actual_raised
                .mul(profit_rate)
                .mul(money_utilize_blocks)
                .div(10000)
                .div(year);
        promised_repay = actual_raised.add(interest);
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
                status = ProjectStatus.Rolling;
                emit ProjectRolling(id);
                again = true;
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
        uint256 profit_total = promised_repay.mul(amount).div(actual_raised);
        uint256 this_usdt_balance = USDT_address.balanceOf(address(this));
        require(
            this_usdt_balance > 0,
            "MoneyDaoFixedRaisingFullReleaseTemplate: no balance"
        );
        if (profit_total > this_usdt_balance) {
            profit_total = this_usdt_balance;
        }
        USDT_address.safeTransfer(account, profit_total);
        return (amount, amount);
    }
}
