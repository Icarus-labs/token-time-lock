// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

interface IPriceFeed {
    // get price in USDT
    function from_usdt_to_token(uint256 amount, address token)
        external
        view
        returns (uint256, uint256);
}
