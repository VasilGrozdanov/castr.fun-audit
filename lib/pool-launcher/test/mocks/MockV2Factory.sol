// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IV2Factory} from "src/external/IV2Factory.sol";

contract MockV2Factory is IV2Factory {
    function implementation() external pure returns (address) {
        return address(0);
    }

    function isPool(address pool) external view returns (bool) {}
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address) {}
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool) {}
}
