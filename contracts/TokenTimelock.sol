// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/**
 * @dev A token holder contract that will allow a beneficiary to extract the
 * tokens after a given release time.
 *
 * Useful for simple vesting schedules like "advisors get all of their tokens
 * after 1 year".
 */
contract TokenTimelock {
    using SafeERC20 for IERC20;

    // beneficiary of tokens after they are released
    address public beneficiary;

    // timestamp when token release is enabled
    uint256 public releaseTime;

    constructor (address beneficiary_) public {
        beneficiary = beneficiary_;
        releaseTime = block.timestamp + 30 days;
    }

    function release(address token) public virtual {
        require(block.timestamp >= releaseTime, "TokenTimelock: current time is before release time");
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "TokenTimelock: no tokens to release");
        IERC20(token).safeTransfer(beneficiary, amount);
    }
}
