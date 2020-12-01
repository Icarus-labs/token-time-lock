// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./HasConstantSlots.sol";
import "./ProjectStatus.sol";

interface IBaseProjectTemplate {
    function setName(string calldata _name) external;

    function insurance_paid() external returns (bool);

    function mark_insurance_paid() external;

    function platform_invest(address account, uint256 amount) external;

    function platform_liquidate(address account)
        external
        returns (uint256, uint256);

    function platform_repay(address account) external returns (uint256);

    function platform_refund(address account) external returns (uint256);

    function heartbeat() external;

    function transferOwnership(address) external;

    function totalSupply() external returns (uint256);

    function max_amount() external returns (uint256);

    function actual_raised() external returns (uint256);

    function status() external returns (ProjectStatus);
}

interface IBaseProjectFactory {
    function instantiate(bytes32 project_id, string calldata symbol)
        external
        returns (address);
}

interface IPriceFeed {
    // get price in USDT
    function from_usdt_to_token(uint256 amount, address token)
        external
        returns (uint256, uint256);
}

struct Project {
    address payable addr;
    address payable owner;
}

contract MiningEco is HasConstantSlots {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 USDT_address;
    bool public initialized;
    uint256 public fee_rate;
    uint256 public insurance_rate;
    address public platform_token;
    address payable public insurance_vault;
    address public price_feed;
    uint256 public total_raised;
    uint256 public total_deposit;

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

    modifier isManager() {
        address manager;
        bytes32 slot = _MANAGER_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            manager := sload(slot)
        }
        require(msg.sender == manager, "MiningEco: only manager");
        _;
    }

    modifier uniqueProjectId(bytes32 id) {
        require(
            projects[id].addr == address(0),
            "MiningEco: project id conflicts"
        );
        _;
    }

    modifier onlyProjects() {
        require(
            projects_by_address[msg.sender] != bytes32(""),
            "MiningEco: only valid projects"
        );
        _;
    }

    event ProjectCreated(uint256 template_id, bytes32 project_id, address who);
    event ProjectInsurancePaid(bytes32 projectid, uint256, address who);

    function initialize(
        address token,
        address usdt,
        address payable vault
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
        insurance_vault = vault;
        USDT_address = IERC20(usdt);
        fee_rate = 50;
        insurance_rate = 1000;

        slot = _MANAGER_SLOT;
        address _sender = msg.sender;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _sender)
        }
        initialized = true;
    }

    function set_price_feed(address _price_feed) public isManager {
        require(_price_feed != address(0), "MiningEco: wrong address");
        price_feed = _price_feed;
    }

    function set_platform_token(address addr) public isManager {
        require(addr != address(0), "MiningEco: wrong address");
        platform_token = addr;
    }

    function set_insurance_vault(address payable vault) public isManager {
        insurance_vault = vault;
    }

    function set_usdt(address a) public isManager {
        USDT_address = IERC20(a);
    }

    function set_template(uint256 i, address projectTemplate) public isManager {
        if (projectTemplate == address(0)) {
            delete template_gallery[i];
        } else {
            template_gallery[i] = projectTemplate;
        }
    }

    function invest(bytes32 project_id, uint256 amount)
        external
        projectIdExists(project_id)
    {
        address project_address = projects[project_id].addr;
        _invest(project_address, amount);
        total_raised = total_raised.add(amount);
        total_deposit = total_deposit.add(amount);
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
    }

    function repay(bytes32 project_id) external projectIdExists(project_id) {
        address project_address = projects[project_id].addr;
        uint256 amt =
            IBaseProjectTemplate(project_address).platform_repay(msg.sender);
        _deduct_total_deposit(amt);
    }

    function refund(bytes32 project_id) external projectIdExists(project_id) {
        address project_address = projects[project_id].addr;
        uint256 amt =
            IBaseProjectTemplate(project_address).platform_refund(
                project_address
            );
        _deduct_total_deposit(amt);
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
        uint256 fee = max_amount.mul(fee_rate).div(10000);
        IERC20(platform_token).safeTransferFrom(msg.sender, address(this), fee);
        require(
            template_gallery[template_id] != address(0),
            "MiningEco: unknown template"
        );
        address project_addr =
            IBaseProjectFactory(template_gallery[template_id]).instantiate(
                project_id,
                symbol
            );
        Project memory p =
            Project({addr: payable(project_addr), owner: msg.sender});
        projects[project_id] = p;
        projects_by_address[project_addr] = project_id;
        _append_new_project_to_user(msg.sender, project_id);
        if (init_calldata.length > 0) {
            project_addr.functionCall(init_calldata);
        }
        IBaseProjectTemplate(project_addr).transferOwnership(msg.sender);

        emit ProjectCreated(template_id, project_id, msg.sender);
    }

    function pay_insurance(bytes32 projectid)
        public
        projectIdExists(projectid)
    {
        address project = projects[projectid].addr;
        require(
            false == IBaseProjectTemplate(project).insurance_paid(),
            "MiningEco: insurance paid"
        );
        IBaseProjectTemplate(project).heartbeat();
        require(
            IBaseProjectTemplate(project).status() == ProjectStatus.Succeeded,
            "MiningEco: not succeeded for insurance"
        );
        uint256 raised = IBaseProjectTemplate(project).actual_raised();
        uint256 insurance = usdt_to_platform_token(raised.div(10));
        IERC20(platform_token).safeTransferFrom(
            msg.sender,
            insurance_vault,
            insurance
        );
        IBaseProjectTemplate(project).mark_insurance_paid();

        emit ProjectInsurancePaid(projectid, insurance, msg.sender);
    }

    function usdt_to_platform_token(uint256 amount) public returns (uint256) {
        if (price_feed == address(0)) {
            // 1 : 1
            return amount;
        } else {
            (uint256 token_amount, uint256 ts) =
                IPriceFeed(price_feed).from_usdt_to_token(
                    amount,
                    platform_token
                );
            return token_amount;
        }
    }

    function _invest(address project_address, uint256 amount) internal {
        uint256 supply = IBaseProjectTemplate(project_address).totalSupply();
        uint256 max = IBaseProjectTemplate(project_address).max_amount();

        uint256 investment = amount;
        if (max.sub(supply) < amount) {
            investment = max.sub(supply);
        }

        // hold the investment at our own disposal
        USDT_address.safeTransferFrom(msg.sender, address(this), investment);
        // mint project token to investor
        IBaseProjectTemplate(project_address).platform_invest(
            msg.sender,
            investment
        );
        // lock investment in the project address
        USDT_address.safeTransfer(project_address, investment);
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
