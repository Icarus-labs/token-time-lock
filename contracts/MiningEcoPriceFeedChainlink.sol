// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract MiningEcoPriceFeedChainlink {
    using SafeMath for uint256;

    AggregatorV3Interface internal priceFeed;

    /**
     * Network: Kovan
     * Aggregator: TRX/USD
     * Address: 0xf94800e6e36b0dc860f6f31e7cdf1086099e8c0e
     */
    constructor() public {
        priceFeed = AggregatorV3Interface(
            0xf94800E6e36b0dc860F6f31e7cDf1086099E8c0E
        );
    }

    function from_usdt_to_token(uint256 amount, address token)
        external
        view
        returns (uint256, uint256)
    {
        (
            uint80 roundID,
            int256 price,
            uint256 startedAt,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        require(
            price >= 0,
            "MiningEcoPriceFeedChainlink: unexpected neg price"
        );
        uint256 dec = 10**priceFeed.decimals();
        return (amount.mul(dec).div(uint256(price)), timeStamp);
    }
}
