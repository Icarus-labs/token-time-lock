// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

interface IProjectAudit {
    function audit_end() external view returns (uint256);
}
