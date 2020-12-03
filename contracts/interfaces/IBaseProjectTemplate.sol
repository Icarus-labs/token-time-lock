// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "../ProjectStatus.sol";

interface IBaseProjectTemplate {
    function setName(string calldata _name) external;

    function insurance_paid() external view returns (bool);

    function mark_insurance_paid() external;

    function platform_audit(bool) external;

    function platform_invest(address account, uint256 amount) external;

    function platform_liquidate(address account)
        external
        returns (uint256, uint256);

    function platform_repay(address account) external returns (uint256);

    function platform_refund(address account) external returns (uint256);

    function heartbeat() external;

    function max_amount() external view returns (uint256);

    function actual_raised() external view returns (uint256);

    function status() external view returns (ProjectStatus);
}
