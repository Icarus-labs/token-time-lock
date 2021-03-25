// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

pragma experimental ABIEncoderV2;

import "./BaseProjectTemplate.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SwapImpl is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant BLOCKS_PER_DAY = 10;

    uint256 public start_time;
    uint256 public soldQty = 0;
    uint256 public totalToken = 0;
    uint256 public unsoldToken = 0;

    bytes32 public id;
    string public symbol;
    uint256 public ratio;
    address public platform_addr;
    IERC20 public token_addr;

    // VotingPhase[] phases;
    // ReplanVotes replan_votes;
    // mapping(address => bool) who_can_replan;

    // event ProjectPhaseChange(bytes32 project_id, uint256 phaseid);
    // event ReplanVoteCast(address voter, bool support, uint256 votes);

    constructor(
        bytes32 _id,
        string memory _symbol,
        uint256 _ratio,
        address _platform,
        address _token
    ) public {
        id = _id;
        symbol = _symbol;
        ratio = _ratio;
        platform_addr = _platform;
        token_addr = IERC20(_token);
    }

    modifier isOpen {
        require(start_time > 0 && block.timestamp > start_time);
        _;
    }

    modifier hasToken {
        unsoldToken = token_addr.balanceOf(address(this));
        require(unsoldToken > 0);
        if (totalToken == 0) {
          totalToken = unsoldToken;
        }
        _;
    }

    receive() external payable isOpen hasToken {
        _swapToken(msg.sender, msg.value);
    }

    function _swapToken(address payable recipient, uint256 receivedEth) internal {
        // require(receivedEth >= 0.01 ether);

        uint256 tokenSold = _convertToToken(receivedEth);

        token_addr.safeTransfer(recipient, tokenSold);
        uint256 diff = receivedEth.sub(tokenSold.div(ratio));
        if (diff > 0) {
            // 退回多余的eth
            recipient.transfer(diff);
        }
    }

    function _convertToToken(uint256 ethAmount) internal view returns (uint256 tokenToSell) {
        if (unsoldToken >= ethAmount.mul(ratio)) {
          tokenToSell = ethAmount.mul(ratio);
        } else {
          tokenToSell = unsoldToken;
        }
    }

    function transferOwnership(address a) public virtual override onlyOwner {
        super.transferOwnership(a);
    }

    function set_start_time(uint256 _start_time) public onlyOwner {
        start_time = _start_time;
    }
}
