// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "./TemplateInitType.sol";

abstract contract BaseProjectFactory {
    address public platform;
    TemplateInitType public init_type;

    modifier onlyPlatform() {
        require(msg.sender == platform, "BaseProjectFactory: only platform");
        _;
    }

    constructor(address _platform, TemplateInitType _init_type) public {
        platform = _platform;
        init_type = _init_type;
    }

    function instantiate(bytes32 project_id, string calldata symbol)
        public
        virtual
        returns (address);
}
