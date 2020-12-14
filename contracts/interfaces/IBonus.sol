// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

interface IBonus {
    function incoming_investment(
        bytes32 project_id,
        address who,
        uint256 amount
    ) external;
}
