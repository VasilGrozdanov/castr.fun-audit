// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {ICLFactory} from "src/external/ICLFactory.sol";

contract MockCLFactory is ICLFactory {
    function poolImplementation() external pure returns (address pool) {}
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool) {}
    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96)
        external
        returns (address pool)
    {}
}
