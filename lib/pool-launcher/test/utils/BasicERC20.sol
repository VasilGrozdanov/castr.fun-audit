// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BasicERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint256 mint) ERC20(name, symbol) {
        _mint(msg.sender, mint);
    }
}
