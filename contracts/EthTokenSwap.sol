// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract EthTokenSwap is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public start_time;
    uint256 public finish_time;
    uint256 public totalToken;
    uint256 public unsoldToken;

    uint256 public id;
    string public symbol;
    uint256 public ratio;
    address public platform_addr;
    IERC20 public token_addr;

    constructor(
        uint256 _id,
        string memory _symbol,
        uint256 _ratio,
        uint256 _finish_time,
        address _platform,
        address _token
    ) public {
        id = _id;
        symbol = _symbol;
        ratio = _ratio;
        platform_addr = _platform;
        token_addr = IERC20(_token);
        start_time = now;
        finish_time = _finish_time;
    }

    modifier isOpen {
        require(start_time > 0 && block.timestamp > start_time);
        _;
    }

    modifier hasToken {
        require(token_addr.balanceOf(address(this)) > 0);
        if (totalToken == 0) {
          totalToken = token_addr.balanceOf(address(this));
          unsoldToken = totalToken;
        }
        _;
    }

    receive() external payable isOpen hasToken {
        // require(block.timestamp > start_time || block.timestamp < finish_time, "the auction is closed");
        // require(receivedEth >= 0.01 ether);
        uint256 tokenToSell;
        if (token_addr.balanceOf(address(this)) >= msg.value.mul(ratio)) {
          tokenToSell = msg.value.mul(ratio);
        } else {
          tokenToSell = token_addr.balanceOf(address(this));
        }

        token_addr.safeTransfer(msg.sender, tokenToSell);
        unsoldToken = unsoldToken.sub(tokenToSell);
        uint256 diff = msg.value.sub(tokenToSell.div(ratio));
        if (diff > 0) {
            // 退回多余的eth
            msg.sender.transfer(diff);
        }
    }

    function set_start_time(uint256 _start_time) public onlyOwner {
        start_time = _start_time;
    }

    function set_finish_time(uint256 _finish_time) public onlyOwner {
        finish_time = _finish_time;
    }
}
