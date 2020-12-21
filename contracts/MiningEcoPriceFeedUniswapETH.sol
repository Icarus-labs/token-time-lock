// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

interface IUniswapRouterV2 {
    function getAmountsOut(uint256 amountIn, address[] memory path)
        external
        view
        virtual
        returns (uint256[] memory amounts);
}

contract MiningEcoPriceFeedUniswapETH {
    using SafeMath for uint256;

    uint256 public constant eth_decimals = 18;
    uint256 public constant dada_decimals = 18;
    address public routerv2 = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public dada = 0x54559aD7Ec464af2FC360B9405412eC8bB0F48Ed;
    address public usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function from_usdt_to_token(uint256 amount, address token)
        external
        view
        returns (uint256, uint256)
    {
        address[] memory path = new address[](3);
        path[0] = usdt;
        path[1] = weth;
        path[2] = dada;
        uint256[] memory outs =
            IUniswapRouterV2(routerv2).getAmountsOut(amount, path);
        return (outs[outs.length - 1], 0);
    }
}
