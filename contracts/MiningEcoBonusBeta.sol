// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./ProjectStatus.sol";
import "./interfaces/IBaseProjectTemplate.sol";

interface Platform {
    function projects(bytes32) external returns (address);
}

contract MiningEcoBonusBeta is Ownable {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant EACH_TOTAL = 88888000000000000000000;

    address public platform;
    address public bonus_token;

    mapping(bytes32 => mapping(address => uint256)) public investments;
    mapping(bytes32 => uint256) public total_investment;

    modifier onlyPlatform() {
        require(msg.sender == platform, "MiningEcoBonus: only platform");
        _;
    }

    event Claimed(bytes32, address, uint256);

    constructor(address _platform, address _bonus_token) public {
        platform = _platform;
        bonus_token = _bonus_token;
    }

    function incoming_investment(
        bytes32 project_id,
        address who,
        uint256 amount
    ) public onlyPlatform {
        investments[project_id][who] += amount;
        total_investment[project_id] += amount;
    }

    function claim_investment_bonus(bytes32 project_id) public {
        ProjectStatus ps =
            IBaseProjectTemplate(Platform(platform).projects(project_id))
                .status();
        require(
            ps > ProjectStatus.Succeeded &&
                ps != ProjectStatus.Auditing &&
                ps != ProjectStatus.Audited,
            "MiningEcoBonus: project status error"
        );
        uint256 invest = investments[project_id][msg.sender];

        require(total_investment[project_id] > 0);
        require(invest > 0);

        uint256 claim_amount =
            EACH_TOTAL.mul(invest).div(total_investment[project_id]);
        IERC20(bonus_token).safeTransfer(msg.sender, claim_amount);

        investments[project_id][msg.sender] = 0;
        emit Claimed(project_id, msg.sender, claim_amount);
    }
}
