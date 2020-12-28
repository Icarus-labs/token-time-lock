// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

// import "@openzeppelin/contracts/math/SafeMath.sol";
// import "@openzeppelin/contracts/utils/Address.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";

// contract MiningEcoBonus is Ownable {
//     using Address for address;
//     using SafeMath for uint256;

//     uint256 public constant DAY_IN_SECS = 86400;

//     address public platform;
//     uint256 public current_period;
//     uint256 public last_peroid;

//     mapping(uint256 => uint256) public period_total_investments;
//     mapping(uint256 => mapping(address => uint256)) public investments;
//     mapping(address => uint256) public investor_last_claim_period;

//     uint256[] public period_checkpoint;

//     modifier onlyPlatform() {
//         require(msg.sender == platform, "MiningEcoBonus: only platform");
//         _;
//     }

//     constructor(
//         address _platform,
//         address _bonus_token,
//         uint256 _daily_cap
//     ) public {
//         platform = _platform;
//         current_period = block.number.div(DAY_IN_SECS);
//     }

//     function incoming_investment(
//         bytes32 project_id,
//         address who,
//         uint256 amount
//     ) public {
//         uint256 period = block.number.div(DAY_IN_SECS);

//         // update current_period if necessary
//         if (period.sub(current_period) >= 1) {
//             current_period++;
//         }

//         // snapshot by period
//         investments[period][who] = investments[period][who].add(amount);
//         period_total_investments[period] = period_total_investments[period].add(
//             amount
//         );
//     }

//     function distribute_investment_bonus() public onlyPlatform {
//         require(Platform(platform).status() >= ProjectStatus.Succeeded, "");
//         require(
//             block.number.div(DAY_IN_SECS) - last_period >= 1,
//             "MiningEcoBonus: distribution too frequently"
//         );
//         last_period = block.number.div(DAY_IN_SECS);
//     }

//     function claim_investment_bonus() public {
//         address who = msg.sender;
//         for (
//             uint256 i = investor_last_claim_period[who];
//             i++;
//             i < last_period
//         ) {
//             if (investments[i][who] > 0) {
//                 uint256 amount_to_give =
//                     investments[i][who].mul(total_each_day).div(
//                         period_total_investment[i]
//                     );
//                 SafeERC20(bonus_token).safeTransfer(who, amount_to_give);
//             }
//         }
//         investor_last_claim_period[who] = last_period;
//     }
// }
