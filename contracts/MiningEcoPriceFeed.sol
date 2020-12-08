// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

interface IDecimals {
    function decimals() external view returns (uint256);
}

struct Feed {
    uint256 price;
    uint256 timestamp;
}

contract MiningEcoPriceFeed {
    using SafeMath for uint256;

    uint256 public constant decimals = 8;

    mapping(address => bool) feeds;
    mapping(address => Feed) public data;

    modifier onlyFeed() {
        require(feeds[msg.sender] == true, "MiningEcoPriceFeed: only feed");
        _;
    }

    constructor(address[] memory addrs) public {
        for (uint256 i = 0; i < addrs.length; i++) {
            feeds[addrs[i]] = true;
        }
    }

    function feed(address token, uint256 _data) external onlyFeed {
        data[token] = Feed({price: _data, timestamp: block.timestamp});
    }

    function from_usdt_to_token(uint256 amount, address token)
        external
        view
        returns (uint256, uint256)
    {
        require(
            data[token].price > 0,
            "MiningEcoPriceFeed: unexpected neg price"
        );
        uint256 token_decimals = IDecimals(token).decimals();
        uint256 usdt_decimals = decimals;
        return (
            amount.mul(10**token_decimals).div(data[token].price),
            data[token].timestamp
        );
    }
}
