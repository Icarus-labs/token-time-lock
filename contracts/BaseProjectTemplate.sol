// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

// predefined project FSM
enum ProjectStatus {
    Created, // just created, waiting for details
    Initialized, // ready for raising USDT
    Collecting, // collecting investment
    Refunding, // somehow the project is doomed, refunding all already raised tokens back to investors
    Canceled, // stop to proceed
    Failed, // fail to raise enough amount to proceed
    Succeeded, // enough amount raised, locked in this project, move on to vote-by-phase, aka rolling
    Rolling, // voting to try get certain amount of locked tokens
    PhaseFailed,
    AllPhasesDone,
    Repaying,
    Finished // the project has totally finished its destination
}

abstract contract BaseProjectTemplate is Ownable {
    string public name = "";
    bytes32 public id;
    address public platform;
    ProjectStatus public status;
    uint256 public max_amount;

    constructor(bytes32 _project_id) public {
        id = _project_id;
    }

    function setName(string calldata _name) external {
        name = _name;
    }

    function platform_invest(address account, uint256 amount) external virtual;

    function platform_refund(address account) external virtual;

    function platform_repay(address account) external virtual;
}
