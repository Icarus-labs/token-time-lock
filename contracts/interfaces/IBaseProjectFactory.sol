// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

interface IBaseProjectFactory {
    function instantiate(bytes32 project_id, string calldata symbol)
        external
        returns (address);
}
