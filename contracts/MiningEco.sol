// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ProjectTemplate.sol";
import "./HasConstantSlots.sol";

import "hardhat/console.sol";

interface IBaseProjectTemplate {
    function platform_invest(address account, uint256 amount) external;

    function platform_refund(address account) external;

    function platform_repay(address account) external;
}

struct Project {
    address payable addr;
    address payable owner;
}

contract MiningEco is HasConstantSlots {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 constant USDT_address = IERC20(
        0xdAC17F958D2ee523a2206206994597C13D831ec7
    );

    bool public initialized;

    uint256 public constant fee_rate = 50;

    address public platform_token;
    address payable public insurance_vault;

    mapping(bytes32 => Project) public projects;
    mapping(address => bytes32) public projects_by_address;
    mapping(address => bytes32[]) public users_projects;

    mapping(uint256 => string) templates;

    modifier projectIdExists(bytes32 id) {
        require(
            projects[id].addr != address(0),
            "MiningEco: project doesn't exist"
        );
        _;
    }

    modifier projectAddressExists(address addr) {
        require(
            projects_by_address[addr] != bytes32(0),
            "MiningEco: project doesn't exist"
        );
        _;
    }

    modifier templateIdExists(uint256 id) {
        require(id == 0, "MiningEco: template doesn't exist");
        _;
    }

    modifier isManager() {
        address manager;
        bytes32 slot = _MANAGER_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            manager := sload(slot)
        }
        require(
            msg.sender == manager,
            "MiningEco: only platform manager can call"
        );
        _;
    }

    modifier uniqueProjectId(bytes32 id) {
        require(
            projects[id].addr == address(0),
            "MiningEco: project id is not unique"
        );
        _;
    }

    function initialize(address token, address payable vault) public {
        require(!initialized, "MiningEco: has been initialized");
        address adm;
        bytes32 slot = _ADMIN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
        require(
            adm != address(0),
            "MiningEco: initialize should only called by MiningEcoProxy"
        );

        platform_token = token;
        insurance_vault = vault;

        slot = _MANAGER_SLOT;
        address _sender = msg.sender;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _sender)
        }

        templates[0] = type(ProjectTemplate).name;
    }

    function set_platform_token(address addr) public isManager {
        require(addr != address(0));
        platform_token = addr;
    }

    function set_insurance_vault(address payable vault) public isManager {
        insurance_vault = vault;
    }

    // function get_user_latest_project(address user)
    //     public
    //     view
    //     returns (uint256, address)
    // {
    //     uint256[] storage ps = users_projects[user];
    //     if (ps.length == 0) {
    //         return (0, address(0));
    //     } else {
    //         uint256 id = ps[ps.length - 1];
    //         return (id, projects[id].addr);
    //     }
    // }

    function invest(address project_address, uint256 amount)
        external
        projectAddressExists(project_address)
    {
        _invest(project_address, amount);
    }

    function invest(bytes32 project_id, uint256 amount)
        external
        projectIdExists(project_id)
    {
        address project_address = projects[project_id].addr;
        _invest(project_address, amount);
    }

    function refund(address project_address)
        external
        projectAddressExists(project_address)
    {
        _refund(project_address);
    }

    function refund(bytes32 project_id) external projectIdExists(project_id) {
        address project_address = projects[project_id].addr;
        _refund(project_address);
    }

    function repay(bytes32 project_id) external projectIdExists(project_id) {
        address project_address = projects[project_id].addr;
        _repay(project_address);
    }

    function repay(address project_address)
        external
        projectAddressExists(project_address)
    {
        _repay(project_address);
    }

    function _repay(address project_address) internal {
        require(
            BaseProjectTemplate(project_address).status() ==
                ProjectStatus.Repaying,
            "MiningEco: the project is not in repaying"
        );
        IBaseProjectTemplate(project_address).platform_repay(msg.sender);
    }

    function _refund(address project_address) internal {
        require(
            BaseProjectTemplate(project_address).status() ==
                ProjectStatus.Refunding,
            "MiningEco: the project is not in refunding"
        );
        IBaseProjectTemplate(project_address).platform_refund(msg.sender);
    }

    function _invest(address project_address, uint256 amount) internal {
        uint256 supply = ProjectToken(project_address).totalSupply();
        uint256 max = ProjectTemplate(project_address).max_amount();

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

    // new_project is the main entrance for a project mananger
    // called with template_id, max raising amount and calldata for initialization
    function new_project(
        uint256 template_id,
        bytes32 project_id,
        uint256 max_amount,
        bytes calldata init_calldata
    ) external templateIdExists(template_id) uniqueProjectId(project_id) {
        uint256 fee = max_amount.mul(fee_rate).div(10000);
        IERC20(platform_token).safeTransferFrom(msg.sender, address(this), fee);

        address project_addr = create_project_from_template(
            msg.sender,
            template_id,
            project_id
        );
        Project memory p = Project({
            addr: payable(project_addr),
            owner: msg.sender
        });
        projects[project_id] = p;
        projects_by_address[project_addr] = project_id;
        append_new_project_to_user(msg.sender, project_id);

        if (init_calldata.length > 0) {
            project_addr.functionCall(init_calldata);
        }
    }

    function append_new_project_to_user(address user, bytes32 pid) internal {
        bytes32[] storage pjs = users_projects[user];
        pjs.push(pid);
    }

    function create_project_from_template(
        address owner,
        uint256 template_id,
        bytes32 project_id
    ) internal returns (address p_addr) {
        bytes memory creationCode;
        if (template_id == 0) {
            creationCode = type(ProjectTemplate).creationCode;
        }
        bytes memory bytecode = abi.encodePacked(
            creationCode,
            abi.encode(project_id)
        );
        // this is where the salt can be imported
        // bytes32 salt = keccak256(
        //     abi.encodePacked(owner, template_id, project_id)
        // );
        bytes32 salt = project_id;
        address predict = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        bytes1(0xff),
                        address(this),
                        salt,
                        keccak256(bytecode)
                    )
                )
            )
        );
        require(!predict.isContract(), "MiningEco: address is already taken");
        assembly {
            p_addr := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(
            predict == p_addr,
            "MiningEco: new contract prediction is wrong"
        );
        BaseProjectTemplate(p_addr).transferOwnership(owner);
        return p_addr;
    }
}
