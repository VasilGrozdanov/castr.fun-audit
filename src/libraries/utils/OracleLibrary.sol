// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TickMath} from "@beefyfinance/beefy-contracts/BIFI/utils/TickMath.sol";
import {Math} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/utils/math/Math.sol";
import {console2} from "forge-std/console2.sol";

/// @title Oracle library
/// @notice Provides functions to integrate with V3 pool oracle
library OracleLibrary {
    /// @notice Given a tick and a token amount, calculates the amount of token received in exchange
    /// @param tick Tick value used to calculate the quote
    /// @param baseAmount Amount of token to be converted
    /// @param baseToken Address of an ERC20 token contract used as the baseAmount denomination
    /// @param quoteToken Address of an ERC20 token contract used as the quoteAmount denomination
    /// @return quoteAmount Amount of quoteToken received for baseAmount of baseToken

    function getQuoteAtTick(
        int24 tick,
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) internal pure returns (uint256 quoteAmount) {
        console2.log("call getSqrtRatioAtTick");

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);
        console2.log("sqrtRatioX96:", sqrtRatioX96);
        console2.log("baseAmount:", baseAmount);
        console2.log("baseToken:", baseToken);
        console2.log("quoteToken:", quoteToken);
        console2.log(
            "sqrtRatioX96 <= type(uint128).max:",
            sqrtRatioX96 <= type(uint128).max
        );

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? Math.mulDiv(ratioX192, baseAmount, 1 << 192)
                : Math.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = Math.mulDiv(
                sqrtRatioX96,
                sqrtRatioX96,
                1 << 64
            );
            quoteAmount = baseToken < quoteToken
                ? Math.mulDiv(ratioX128, baseAmount, 1 << 128)
                : Math.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }
}
