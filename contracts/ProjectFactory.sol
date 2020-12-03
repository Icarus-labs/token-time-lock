// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "./ProjectTemplate.sol";
import "./BaseProjectFactory.sol";

contract ProjectFactory is BaseProjectFactory {
    address public USDT_address;

    constructor(address _platform, address usdt)
        public
        BaseProjectFactory(_platform)
    {
        USDT_address = usdt;
    }

    function update_usdt(address usdt) external onlyPlatform {
        USDT_address = usdt;
    }

    function instantiate(bytes32 project_id, string calldata symbol)
        external
        override
        onlyPlatform
        returns (address p_addr)
    {
        ProjectTemplate project =
            new ProjectTemplate(project_id, symbol, platform, USDT_address);
        project.transferOwnership(platform);
        return address(project);
        // bytes memory creationCode = type(ProjectTemplate).creationCode;
        // bytes memory bytecode =
        //     abi.encodePacked(
        //         creationCode,
        //         abi.encode(project_id, symbol, platform, USDT_address)
        //     );
        // address predict =
        //     address(
        //         uint160(
        //             uint256(
        //                 keccak256(
        //                     abi.encodePacked(
        //                         bytes1(0xff),
        //                         address(this),
        //                         project_id,
        //                         keccak256(bytecode)
        //                     )
        //                 )
        //             )
        //         )
        //     );
        // require(
        //     !predict.isContract(),
        //     "ProjectFactory: contract address preoccupied"
        // );
        // assembly {
        //     p_addr := create2(
        //         0,
        //         add(bytecode, 0x20),
        //         mload(bytecode),
        //         project_id
        //     )
        // }
        // require(predict == p_addr, "ProjectFactory: wrong address prediction");
        // ProjectTemplate(p_addr).transferOwnership(platform);
        // return p_addr;
    }
}
