// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

contract HasConstantSlots {
    // bytes32(uint256(keccak256("MiningEco.Platform.Committee")))
    bytes32 constant _COMMITTEE_SLOT =
        0x7090fa6e7ba86497228923d0ffeb304699d149da33caff1cc7c4e8abd5ba6147;

    bytes32 constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
}
