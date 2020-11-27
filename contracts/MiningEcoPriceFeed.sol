// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/math/SafeMath.sol";

struct Feed {
    int256 price;
    uint256 timestamp;
}

contract MiningEcoPriceFeed {
    using SafeMath for uint256;

    uint256 public constant decimals = 8;

    mapping(address => bool) feeds;
    mapping(address => Feed) data;

    modifier onlyFeed() {
        require(feeds[msg.sender] == true, "MiningEcoPriceFeed: only feed");
        _;
    }

    constructor(address[] memory addrs) public {
        for (uint256 i = 0; i < addrs.length; i++) {
            feeds[addrs[i]] = true;
        }
    }

    function feed(address token, int256 _data) external onlyFeed {
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
        uint256 dec = 10**decimals;
        return (
            amount.mul(dec).div(uint256(data[token].price)),
            data[token].timestamp
        );
    }
}
