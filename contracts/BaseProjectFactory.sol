// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

abstract contract BaseProjectFactory {
    address public platform;

    modifier onlyPlatform() {
        require(msg.sender == platform, "BaseProjectFactory: only platform");
        _;
    }

    constructor(address _platform) public {
        platform = _platform;
    }

    function instantiate(bytes32 project_id, string calldata symbol)
        external
        virtual
        returns (address);
}
