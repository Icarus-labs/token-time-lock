// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenSwap is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public start_time;
    uint256 public totalToken;
    uint256 public unsoldToken;

    bytes32 public id;
    string public symbol;
    uint256 public ratio;
    address public platform_addr;
    IERC20 public token_addr_1;
    IERC20 public token_addr_2;

    constructor(
        bytes32 _id,
        string memory _symbol,
        uint256 _ratio,
        address _platform,
        address _token1,
        address _token2
    ) public {
        id = _id;
        symbol = _symbol;
        ratio = _ratio;
        platform_addr = _platform;
        token_addr_1 = IERC20(_token1);
        token_addr_2 = IERC20(_token2);
    }

    modifier isOpen {
        require(start_time > 0 && block.timestamp > start_time);
        _;
    }

    modifier hasToken {
        require(token_addr_2.balanceOf(address(this)) > 0);
        if (totalToken == 0) {
          totalToken = token_addr_2.balanceOf(address(this));
          unsoldToken = totalToken;
        }
        _;
    }

    function swap(uint256 amount) public isOpen hasToken {  // amount用户token1数量
        require(amount > 0, "You need to sell at least some tokens");
        uint256 tokenToSwap;
        if (token_addr_2.balanceOf(address(this)) >= amount.mul(ratio)) { // 待出售的token2
          tokenToSwap = amount.mul(ratio);
        } else {
          tokenToSwap = token_addr_2.balanceOf(address(this));  // tokenToSwap出售token2的数量
        }

        // token_addr_1.safeApprove(address(this), amount);
        token_addr_1.safeTransferFrom(msg.sender, address(this), amount);

        token_addr_2.safeTransfer(msg.sender, tokenToSwap);
        unsoldToken = unsoldToken.sub(tokenToSwap);
        uint256 diff = amount.sub(tokenToSwap.div(ratio));
        if (diff > 0) {
            token_addr_1.safeTransfer(msg.sender, diff);  // 退回多余的token_addr_1
        }
    }

    function set_start_time(uint256 _start_time) public onlyOwner {
        start_time = _start_time;
    }
}
