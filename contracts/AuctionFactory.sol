// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.8.0;

import "./EthTokenSwap.sol";

contract AuctionFactory {
    address public platform;
    mapping(uint256 => address) public auctions;

    modifier onlyPlatform() {
        require(msg.sender == platform, "AuctionFactory: only platform");
        _;
    }

    constructor(address _platform) public {
        platform = _platform;
    }

    function getAuction(uint256 _index) public view returns (address){
        return auctions[_index];
    }

    function instantiate(uint256 auction_id, string calldata symbol, uint256 ratio, uint256 finish_time, address token_addr) public onlyPlatform {
        EthTokenSwap ethtokenswap = new EthTokenSwap(auction_id, symbol, ratio, finish_time, platform, token_addr);
        auctions[auction_id] = address(ethtokenswap);
        ethtokenswap.transferOwnership(platform);
        // return address(ethtokenswap);
        // bytes memory creationCode = type(ProjectTemplate).creationCode;
        // bytes memory bytecode =
        //     abi.encodePacked(
        //         creationCode,
        //         abi.encode(project_id, symbol, platform, USDT_address)
        //     );
        // address predict =
        //     address(
        //         uint160(
        //             uint256(
        //                 keccak256(
        //                     abi.encodePacked(
        //                         bytes1(0xff),
        //                         address(this),
        //                         project_id,
        //                         keccak256(bytecode)
        //                     )
        //                 )
        //             )
        //         )
        //     );
        // require(
        //     !predict.isContract(),
        //     "ProjectFactory: contract address preoccupied"
        // );
        // assembly {
        //     p_addr := create2(
        //         0,
        //         add(bytecode, 0x20),
        //         mload(bytecode),
        //         project_id
        //     )
        // }
        // require(predict == p_addr, "ProjectFactory: wrong address prediction");
        // ProjectTemplate(p_addr).transferOwnership(platform);
        // return p_addr;
    }
}
