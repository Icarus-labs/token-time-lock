// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

interface IUniswapPair {
    function getReserves()
        external
        view
        returns (
            uint256,
            uint256,
            uint256
        );
}

contract MiningEcoPriceFeedUniswap {
    using SafeMath for uint256;

    uint256 public constant usdt_decimals = 6;
    uint256 public constant dada_decimals = 18;
    address public routerv2;
    address public dada;
    address public pair = 0x0Eff94CBD4Bb4B6f1367212Ed04859a32d9C19F9;

    function from_usdt_to_token(uint256 amount, address token)
        external
        view
        returns (uint256, uint256)
    {
        (uint256 dada_r, uint256 usdt_r, uint256 ts) =
            IUniswapPair(pair).getReserves();
        uint256 token_amount = dada_r.mul(amount).div(usdt_r);
        return (token_amount, ts);
    }
}
