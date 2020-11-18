// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MiningEcoProxy is TransparentUpgradeableProxy {
    constructor(
        address _logic,
        address _admin,
        bytes memory _data
    ) public payable TransparentUpgradeableProxy(_logic, _admin, _data) {}
}
