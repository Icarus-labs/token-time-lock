// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

import "./HasConstantSlots.sol";
import "./ProjectStatus.sol";
import "./MiningEcoBonus.sol";
import "./TemplateInitType.sol";

import "./interfaces/IBaseProjectTemplate.sol";
import "./interfaces/IBaseProjectFactory.sol";
import "./interfaces/IPriceFeed.sol";
import "./interfaces/ICommittee.sol";
import "./interfaces/IProjectAudit.sol";
import "./interfaces/IBonus.sol";

struct Project {
    address payable addr;
    uint256 proposal_id;
}

contract MiningEco is HasConstantSlots {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    uint256 public constant DEFAULT_INSURANCE_RATE = 1000;

    IERC20 USDT_address;
    bool public initialized;
    uint256 public fee_rate;
    address public platform_token;
    address payable public insurance_vault;
    address payable public fee_vault;
    address public price_feed;
    uint256 public total_raised;
    uint256 public total_deposit;
    bool public project_audit_by_committee;
    address public audit_committee;
    address public bonus;

    mapping(bytes32 => Project) public projects;
    mapping(address => bytes32) public projects_by_address;
    mapping(address => bytes32[]) public users_projects;
    mapping(uint256 => address) public template_gallery;

    modifier projectIdExists(bytes32 id) {
        require(
            projects[id].addr != address(0),
            "MiningEco: unknown project id"
        );
        _;
    }

    modifier projectAddressExists(address addr) {
        require(
            projects_by_address[addr] != bytes32(0),
            "MiningEco: unknown project address"
        );
        _;
    }

    modifier templateIdExists(uint256 id) {
        require(
            template_gallery[id] != address(0),
            "MiningEco: unknown template"
        );
        _;
    }

    modifier platformInitialized() {
        require(initialized, "MiningEco: platform not initialized");
        _;
    }

    modifier isCommittee() {
        address committee;
        bytes32 slot = _COMMITTEE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            committee := sload(slot)
        }
        require(msg.sender == committee, "MiningEco: only committee");
        _;
    }

    modifier isAuditCommittee() {
        require(
            msg.sender == audit_committee,
            "MiningEco: only audit committee"
        );
        _;
    }

    modifier uniqueProjectId(bytes32 id) {
        require(
            projects[id].addr == address(0),
            "MiningEco: project id conflicts"
        );
        _;
    }

    event NewCommittee(address);
    event NewAuditCommittee(address);
    event ProjectAudit(bytes32 projectid, bool y);
    event ProjectCreated(
        uint256 template_id,
        bytes32 project_id,
        address who,
        address project
    );
    event ProjectInsurancePaid(bytes32 projectid, address who, uint256 amount);
    event ProjectInvest(bytes32 projectid, address investor, uint256 amount);
    event ProjectLiquidate(bytes32 projectid, address investor, uint256 amount);
    event ProjectRefund(bytes32 projectid, address investor, uint256 amount);
    event ProjectRepay(bytes32 projectid, address investor, uint256 amount);
    event ProjectFeeTransfered(uint256 amount, address who);

    function initialize(
        address token,
        address usdt,
        address payable _insurance_vault,
        address payable _fee_vault
    ) public {
        require(!initialized, "MiningEco: already initialized");
        address adm;
        bytes32 slot = _ADMIN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
        require(adm != address(0), "MiningEco: not from proxy");

        platform_token = token;
        insurance_vault = _insurance_vault;
        fee_vault = _fee_vault;
        USDT_address = IERC20(usdt);
        fee_rate = 50;
        audit_committee = msg.sender;
        slot = _COMMITTEE_SLOT;
        address _sender = msg.sender;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _sender)
        }
        initialized = true;
    }

    function set_fee_rate(uint256 _fr) public isCommittee {
        fee_rate = _fr;
    }

    function set_price_feed(address _price_feed) public isCommittee {
        require(_price_feed != address(0), "MiningEco: wrong address");
        price_feed = _price_feed;
    }

    function set_platform_token(address addr) public isCommittee {
        require(addr != address(0), "MiningEco: wrong address");
        platform_token = addr;
    }

    function set_fee_vault(address payable _vault) public isCommittee {
        fee_vault = _vault;
    }

    function set_insurance_vault(address payable vault) public isCommittee {
        insurance_vault = vault;
    }

    function set_usdt(address a) public isCommittee {
        USDT_address = IERC20(a);
    }

    function set_template(uint256 i, address projectTemplate)
        public
        isCommittee
    {
        if (projectTemplate == address(0)) {
            delete template_gallery[i];
        } else {
            template_gallery[i] = projectTemplate;
        }
    }

    function set_bonus(address b) public isCommittee {
        bonus = b;
    }

    function set_new_committee(address _committee) public isCommittee {
        bytes32 slot = _COMMITTEE_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _committee)
        }
        emit NewCommittee(_committee);
    }

    function set_audit_committee(address _committee, bool _need_vote)
        public
        isCommittee
    {
        audit_committee = _committee;
        project_audit_by_committee = _need_vote;
        emit NewAuditCommittee(_committee);
    }

    function committee_address() public view returns (address committee) {
        bytes32 slot = _COMMITTEE_SLOT;
        assembly {
            committee := sload(slot)
        }
        return committee;
    }

    function audit_project(
        bytes32 project_id,
        bool yn,
        uint256 _insurance_rate
    ) public isAuditCommittee projectIdExists(project_id) {
        IBaseProjectTemplate(projects[project_id].addr).platform_audit(
            yn,
            _insurance_rate
        );
        emit ProjectAudit(project_id, yn);
    }

    function invest(bytes32 project_id, uint256 amount)
        external
        projectIdExists(project_id)
    {
        address project_address = projects[project_id].addr;
        uint256 amt = _invest(project_address, amount);
        total_raised = total_raised.add(amt);
        total_deposit = total_deposit.add(amt);
        emit ProjectInvest(project_id, msg.sender, amt);

        if (bonus != address(0)) {
            IBonus(bonus).incoming_investment(project_id, msg.sender, amt);
        }
    }

    function liquidate(bytes32 project_id)
        external
        projectIdExists(project_id)
    {
        address project_address = projects[project_id].addr;
        (uint256 amt, ) =
            IBaseProjectTemplate(project_address).platform_liquidate(
                msg.sender
            );
        _deduct_total_deposit(amt);
        emit ProjectLiquidate(project_id, msg.sender, amt);
    }

    function repay(bytes32 project_id) external projectIdExists(project_id) {
        address project_address = projects[project_id].addr;
        (uint256 amt, ) =
            IBaseProjectTemplate(project_address).platform_repay(msg.sender);
        _deduct_total_deposit(amt);
        emit ProjectRepay(project_id, msg.sender, amt);
    }

    // before project fail, investor can call 'refund' to get back their investment
    // what so ever left
    function refund(bytes32 project_id) external projectIdExists(project_id) {
        address project_address = projects[project_id].addr;
        (uint256 amt, ) =
            IBaseProjectTemplate(project_address).platform_refund(msg.sender);
        _deduct_total_deposit(amt);
        emit ProjectRefund(project_id, msg.sender, amt);
    }

    function _get_insurance_rate_from_calldata(uint256 template_id, bytes calldata init_calldata) internal view returns(uint256 _insurance_rate) {
        TemplateInitType init_type = IBaseProjectFactory(template_gallery[template_id]).init_type();
        bytes calldata calldata_argv = init_calldata[4:];
        if (init_type == TemplateInitType.Project) {
             (,,,,,,,,, _insurance_rate) = abi.decode(calldata_argv, (address,uint256,uint256,uint256,uint256,uint256,uint256,uint256[],address[],uint256));
        } else if (init_type == TemplateInitType.MoneyDao) {
             (,,,,,, _insurance_rate) = abi.decode(calldata_argv, (address,uint256,uint256,uint256,uint256,uint256,uint256));
        } else if (init_type == TemplateInitType.MoneyDaoFixedRaising) {
            (,,,,,,, _insurance_rate) = abi.decode(calldata_argv, (address,uint256,uint256,uint256,uint256,uint256,uint256,uint256));
        } else {
            _insurance_rate = DEFAULT_INSURANCE_RATE;
        }
        return _insurance_rate;
    }

    // new_project is the main entrance for a project mananger
    // called with template_id, max raising amount and calldata for initialization
    function new_project(
        uint256 template_id,
        bytes32 project_id,
        uint256 max_amount,
        string calldata symbol,
        bytes calldata init_calldata
    )
        external
        platformInitialized
        templateIdExists(template_id)
        uniqueProjectId(project_id)
    {
        require(
            template_gallery[template_id] != address(0),
            "MiningEco: unknown template"
        );
        USDT_address.safeTransferFrom(
            msg.sender,
            fee_vault,
            max_amount.mul(fee_rate).div(10000)
        );

        uint256 _insurance_rate = _get_insurance_rate_from_calldata(template_id, init_calldata);

        address project_addr =
            IBaseProjectFactory(template_gallery[template_id]).instantiate(
                project_id,
                symbol
            );
        Project memory p =
            Project({addr: payable(project_addr), proposal_id: 0});
        if (init_calldata.length > 0) {
            project_addr.functionCall(init_calldata);
        }
        Ownable(project_addr).transferOwnership(msg.sender);

        emit ProjectCreated(template_id, project_id, msg.sender, project_addr);
        if (project_audit_by_committee) {
            address[] memory targets = new address[](1);
            targets[0] = address(this);
            uint256[] memory values = new uint256[](1);
            values[0] = 0;
            string[] memory sigs = new string[](1);
            bytes[] memory calldatas = new bytes[](1);
            calldatas[0] = abi.encodeWithSelector(
                this.audit_project.selector,
                project_id,
                true,
                _insurance_rate
            );
            p.proposal_id = ICommittee(audit_committee).propose(
                targets,
                values,
                sigs,
                calldatas,
                block.number + 1,
                IProjectAudit(project_addr).audit_end()
            );
        }

        projects[project_id] = p;
        projects_by_address[project_addr] = project_id;
        _append_new_project_to_user(msg.sender, project_id);
    }

    function insurance(bytes32 projectid)
        public
        view
        projectIdExists(projectid)
        returns (uint256)
    {
        address project = projects[projectid].addr;
        uint256 raised = IBaseProjectTemplate(project).actual_raised();
        require(
            IBaseProjectTemplate(project).actual_project_status() ==
                ProjectStatus.Succeeded,
            "MiningEco: not succeeded for insurance"
        );
        uint256 insurance_rate = IBaseProjectTemplate(project).insurance_rate();
        uint256 insurance_amt;
        if (insurance_rate > 0) {
            insurance_amt = usdt_to_platform_token(
                raised.mul(insurance_rate).div(10000)
            );
        }
        return insurance_amt;
    }

    function project_status(bytes32 projectid)
        public
        view
        projectIdExists(projectid)
        returns (ProjectStatus)
    {
        address project = projects[projectid].addr;
        return IBaseProjectTemplate(project).status();
    }

    function pay_insurance(bytes32 projectid)
        public
        projectIdExists(projectid)
    {
        address project = projects[projectid].addr;
        IBaseProjectTemplate(project).heartbeat();
        require(
            IBaseProjectTemplate(project).status() == ProjectStatus.Succeeded,
            "MiningEco: not succeeded for insurance"
        );
        uint256 raised = IBaseProjectTemplate(project).actual_raised();
        uint256 insurance_rate = IBaseProjectTemplate(project).insurance_rate();
        uint256 insurance_amt;
        if (insurance_rate > 0) {
            insurance_amt = usdt_to_platform_token(
                raised.mul(insurance_rate).div(10000)
            );
            IERC20(platform_token).safeTransferFrom(
                msg.sender,
                insurance_vault,
                insurance_amt
            );
        }
        IBaseProjectTemplate(project).mark_insurance_paid();
        emit ProjectInsurancePaid(projectid, msg.sender, insurance_amt);
    }

    function usdt_to_platform_token(uint256 amount)
        public
        view
        returns (uint256)
    {
        if (price_feed == address(0)) {
            // 0.045$
            return amount.mul(10**18).div(10**6).mul(1000).div(45);
        } else {
            (uint256 token_amount, uint256 ts) =
                IPriceFeed(price_feed).from_usdt_to_token(
                    amount,
                    platform_token
                );
            return token_amount;
        }
    }

    function transfer_token(
        address token,
        uint256 amount,
        address to_account
    ) public isCommittee {
        IERC20(token).safeTransfer(to_account, amount);
    }

    function _invest(address project_address, uint256 amount)
        internal
        returns (uint256)
    {
        // hold the investment at our own disposal
        USDT_address.safeTransferFrom(msg.sender, address(this), amount);
        // mint project token to investor
        uint256 investment =
            IBaseProjectTemplate(project_address).platform_invest(
                msg.sender,
                amount
            );
        // lock investment in the project address
        USDT_address.safeTransfer(project_address, investment);
        if (amount.sub(investment) > 0) {
            USDT_address.safeTransfer(msg.sender, amount.sub(investment));
        }
        return investment;
    }

    function _append_new_project_to_user(address user, bytes32 pid) internal {
        bytes32[] storage pjs = users_projects[user];
        pjs.push(pid);
    }

    function _deduct_total_deposit(uint256 amount) internal {
        require(
            total_deposit.div(amount) >= 0,
            "MiningEco: illegal total deposit deduction"
        );
        total_deposit = total_deposit.div(amount);
    }
}
