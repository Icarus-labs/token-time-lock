// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "./MoneyDaoFixedRaisingFullReleaseTemplate.sol";
import "./BaseProjectFactory.sol";
import "./TemplateInitType.sol";

contract MoneyDaoFixedRaisingFullReleaseFactory is BaseProjectFactory {
    address public USDT_address;

    constructor(address _platform, address usdt)
        public
        BaseProjectFactory(_platform, TemplateInitType.MoneyDaoFixedRaising)
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
        MoneyDaoFixedRaisingFullReleaseTemplate project =
            new MoneyDaoFixedRaisingFullReleaseTemplate(
                project_id,
                symbol,
                platform,
                USDT_address
            );
        project.transferOwnership(platform);
        return address(project);
    }
}
