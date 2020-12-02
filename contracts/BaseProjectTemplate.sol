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
    uint256 public insurance_deadline;
    bool public insurance_paid;

    modifier platformRequired() {
        require(
            msg.sender == platform,
            "ProjectTemplate: only platform is allowed to call this"
        );
        _;
    }

    event VoteCast(address who, uint256 phase_id, bool support, uint256 votes);

    constructor(bytes32 projectid, address _platform) public {
        id = projectid;
        platform = _platform;
    }

    function setName(string calldata _name) external onlyOwner {
        name = _name;
    }

    function mark_insurance_paid() public platformRequired {
        insurance_paid = true;
    }

    function platform_audit(bool pass) external virtual;

    function platform_invest(address account, uint256 amount) external virtual;

    function platform_refund(address account)
        external
        virtual
        returns (uint256);

    function platform_repay(address account) external virtual returns (uint256);

    function platform_liquidate(address account)
        external
        virtual
        returns (uint256, uint256);

    function heartbeat() external virtual;

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
    }
}
