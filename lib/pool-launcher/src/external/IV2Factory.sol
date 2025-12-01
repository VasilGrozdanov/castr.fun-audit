// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IV2Factory {
    function implementation() external view returns (address);
    function isPool(address pool) external view returns (bool);
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);
}
