// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "./ProjectToken.sol";
import "./ProjectStatus.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

abstract contract BaseProjectTemplate is Ownable, ProjectToken {
    using Address for address;

    string public name = "";
    bytes32 public id;
    address public platform;
    ProjectStatus public status;
    uint256 public max_amount;
    uint256 public min_amount;
    uint256 public actual_raised;
    uint256 public insurance_deadline;
    uint256 public insurance_rate;
    address public fund_receiver;
    uint256 public audit_end;
    uint256 public raise_start;
    uint256 public raise_end;

    modifier platformRequired() {
        require(
            msg.sender == platform,
            "ProjectTemplate: only platform is allowed to call this"
        );
        _;
    }

    event VoteCast(address who, uint256 phase_id, bool support, uint256 votes);

    event ProjectRaising(bytes32 project_id);
    event ProjectFailed(bytes32 project_id);
    event ProjectAudited(bytes32 project_id);
    event ProjectSucceeded(bytes32 project_id);
    event ProjectRefunding(bytes32 project_id);
    event ProjectInsuranceFailure(bytes32 project_id);
    event ProjectRolling(bytes32 project_id);
    event ProjectLiquidating(bytes32 project_id);
    event ProjectRepaying(bytes32 project_id);
    event ProjectFinished(bytes32 project_id);

    constructor(
        bytes32 projectid,
        address _platform,
        string memory _symbol
    ) public ProjectToken(_symbol) {
        id = projectid;
        platform = _platform;
    }

    function setName(string calldata _name) public onlyOwner {
        name = _name;
    }

    function mark_insurance_paid() public virtual platformRequired {
        status = ProjectStatus.InsurancePaid;
    }

    function _platform_audit(bool pass, uint256 _insurance_rate) internal {
        if (pass) {
            status = ProjectStatus.Audited;
            insurance_rate = _insurance_rate;
            emit ProjectAudited(id);
        } else {
            status = ProjectStatus.Failed;
            emit ProjectFailed(id);
        }
    }

    function platform_audit(bool _pass, uint256 _insurance_rate)
        public
        virtual
    {
        require(
            status == ProjectStatus.Auditing && block.number < audit_end,
            "ProjectTemplate: no audit window"
        );
        _platform_audit(_pass, _insurance_rate);
    }

    function _platform_invest(address account, uint256 amount)
        internal
        returns (uint256)
    {
        uint256 invest_amt = amount;
        if (max_amount < actual_raised + amount) {
            invest_amt = max_amount - actual_raised;
        }

        _mint(account, invest_amt);

        actual_raised = actual_raised.add(invest_amt);
        if (actual_raised >= min_amount && status == ProjectStatus.Raising) {
            status = ProjectStatus.Succeeded;
            emit ProjectSucceeded(id);
        }
        return invest_amt;
    }

    function platform_invest(address account, uint256 amount)
        public
        virtual
        returns (uint256)
    {
        require(
            status == ProjectStatus.Raising ||
                status == ProjectStatus.Succeeded,
            "BaseProjectTemplate: not raising"
        );
        require(
            max_amount > actual_raised,
            "BaseProjectTemplate: reach max amount"
        );
        return _platform_invest(account, amount);
    }

    function _recycle_options(address account) internal returns (uint256) {
        uint256 balance = _balances[account];
        require(balance > 0);
        _transfer(account, address(this), balance);
        return balance;
    }

    function platform_refund(address account)
        public
        virtual
        returns (uint256, uint256)
    {
        require(
            status == ProjectStatus.Refunding,
            "BaseProjectTemplate: not in refunding"
        );
        uint256 amt = _recycle_options(account);
        return (amt, amt);
    }

    function platform_repay(address account)
        public
        virtual
        returns (uint256, uint256)
    {
        require(
            status == ProjectStatus.Repaying,
            "BaseProjectTemplate: not in repaying"
        );
        uint256 amt = _recycle_options(account);
        return (amt, amt);
    }

    function platform_liquidate(address account)
        public
        virtual
        returns (uint256, uint256)
    {
        require(
            status == ProjectStatus.Liquidating,
            "BaseProjectTemplate: not in liquidating"
        );
        uint256 amt = _recycle_options(account);
        return (amt, amt);
    }

    function heartbeat() public virtual;

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
    }
}
