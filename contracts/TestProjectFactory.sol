// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "./TestProjectTemplate.sol";
import "./BaseProjectFactory.sol";
import "./TemplateInitType.sol";

contract TestProjectFactory is BaseProjectFactory {
    address public USDT_address;

    constructor(address _platform, address usdt)
        public
        BaseProjectFactory(_platform, TemplateInitType.Project)
    {
        USDT_address = usdt;
    }

    function update_usdt(address usdt) external onlyPlatform {
        USDT_address = usdt;
    }

    function instantiate(bytes32 project_id, string calldata symbol)
        public
        override
        onlyPlatform
        returns (address p_addr)
    {
        TestProjectTemplate instance =
            new TestProjectTemplate(project_id, symbol, platform, USDT_address);
        instance.transferOwnership(platform);
        return address(instance);
        // bytes memory creationCode = type(TestProjectTemplate).creationCode;
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
        //     "TestProjectFactory: contract address preoccupied"
        // );
        // assembly {
        //     p_addr := create2(
        //         0,
        //         add(bytecode, 0x20),
        //         mload(bytecode),
        //         project_id
        //     )
        // }
        // require(
        //     predict == p_addr,
        //     "TestProjectFactory: wrong address prediction"
        // );
        // BaseProjectTemplate(p_addr).transferOwnership(platform);
        // return p_addr;
    }
}
