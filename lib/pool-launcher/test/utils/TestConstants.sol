// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

abstract contract TestConstants {
    uint256 public constant TOKEN_1 = 1e18;
    uint256 public constant USDC_1 = 1e6;
    uint256 public constant POOL_1 = 1e9;
    int24 public constant TICK_SPACING_200 = 200;
    // minimum liquidity for v2 pools
    uint256 internal constant MINIMUM_LIQUIDITY = 10 ** 3;

    // maximum number of tokens, used in fuzzing
    uint256 public constant MAX_TOKENS = 1e40;
    uint256 public constant MAX_BPS = 10_000;

    address public constant OLD_NFPM_OP = 0xbB5DFE1380333CEE4c2EeBd7202c80dE2256AdF4;
}
