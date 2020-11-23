// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ProjectTemplate.sol";
import "./HasConstantSlots.sol";

interface IBaseProjectTemplate {
    function platform_invest(address account, uint256 amount) external;
}

struct Project {
    address payable addr;
    address payable owner;
}

contract MiningEco is HasConstantSlots {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    IERC20 constant USDT_address =
        IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    bool public initialized;

    uint256 public constant fee_rate = 50;

    address public platform_token;
    address payable public insurance_vault;

    mapping(bytes32 => Project) public projects;
    mapping(address => bytes32) public projects_by_address;
    mapping(address => bytes32[]) public users_projects;

    mapping(uint256 => string) public templates;

    modifier projectIdExists(bytes32 id) {
        require(projects[id].addr != address(0));
        _;
    }

    modifier projectAddressExists(address addr) {
        require(projects_by_address[addr] != bytes32(0));
        _;
    }

    modifier templateIdExists(uint256 id) {
        require(id == 0);
        _;
    }

    modifier platformInitialized() {
        require(initialized);
        _;
    }

    modifier isManager() {
        address manager;
        bytes32 slot = _MANAGER_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            manager := sload(slot)
        }
        require(msg.sender == manager);
        _;
    }

    modifier uniqueProjectId(bytes32 id) {
        require(projects[id].addr == address(0));
        _;
    }

    function initialize(address token, address payable vault) public {
        require(!initialized);
        address adm;
        bytes32 slot = _ADMIN_SLOT;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            adm := sload(slot)
        }
        require(adm != address(0));

        platform_token = token;
        insurance_vault = vault;

        slot = _MANAGER_SLOT;
        address _sender = msg.sender;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            sstore(slot, _sender)
        }
        templates[0] = type(ProjectTemplate).name;
        initialized = true;
    }

    function set_platform_token(address addr) public isManager {
        require(addr != address(0));
        platform_token = addr;
    }

    function set_insurance_vault(address payable vault) public isManager {
        insurance_vault = vault;
    }

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

        address project_addr =
            create_project_from_template(
                msg.sender,
                template_id,
                project_id,
                symbol
            );
        Project memory p =
            Project({addr: payable(project_addr), owner: msg.sender});
        projects[project_id] = p;
        projects_by_address[project_addr] = project_id;
        append_new_project_to_user(msg.sender, project_id);
        if (init_calldata.length > 0) {
            project_addr.functionCall(init_calldata);
        }
        BaseProjectTemplate(project_addr).transferOwnership(msg.sender);
    }

    function append_new_project_to_user(address user, bytes32 pid) internal {
        bytes32[] storage pjs = users_projects[user];
        pjs.push(pid);
    }

    function create_project_from_template(
        address owner,
        uint256 template_id,
        bytes32 project_id,
        string memory symbol
    ) internal returns (address p_addr) {
        bytes memory creationCode;
        if (template_id == 0) {
            creationCode = type(ProjectTemplate).creationCode;
        }
        bytes memory bytecode =
            abi.encodePacked(
                creationCode,
                abi.encode(address(this), project_id, symbol)
            );
        // this is where the salt can be imported
        // bytes32 salt = keccak256(
        //     abi.encodePacked(owner, template_id, project_id)
        // );
        address predict =
            address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                bytes1(0xff),
                                address(this),
                                uint256(project_id),
                                keccak256(bytecode)
                            )
                        )
                    )
                )
            );
        require(!predict.isContract());
        assembly {
            p_addr := create2(
                0,
                add(bytecode, 0x20),
                mload(bytecode),
                project_id
            )
        }
        require(predict == p_addr);
        return p_addr;
    }
}
