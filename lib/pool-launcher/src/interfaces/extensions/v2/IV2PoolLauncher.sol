// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IV2Factory} from "../../../external/IV2Factory.sol";
import {IPoolLauncher} from "../../IPoolLauncher.sol";

interface IV2PoolLauncher is IPoolLauncher {
    struct LaunchParams {
        /// @notice address of the pool launcher token
        address poolLauncherToken;
        /// @notice address of the token to pair with
        address tokenToPair;
        /// @notice stable/volatile type of the pool
        bool stable;
        /// @notice Liquidity params
        LiquidityParams liquidity;
    }

    struct LiquidityParams {
        /// @notice amount of pool launcher token to add to the pool
        uint256 amountPoolLauncherToken;
        /// @notice amount of token to add to the pool
        uint256 amountTokenToPair;
        /// @notice minimum amount of pool launcher token to add to the pool
        uint256 amountPoolLauncherTokenMin;
        /// @notice minimum amount of token to add to the pool
        uint256 amountTokenToPairMin;
        /// @notice duration for which to lock the liquidity (0 = no lock, type(uint32).max = infinite lock)
        uint32 lockDuration;
    }

    /**
     * @notice Launch a new v2 pool launcher pool
     * @param _params launch parameters
     * @param _recipient address to receive the pool launcher pool liquidity
     * @param _refundAddress address to refund any excess tokens
     * @return The newly created pool launcher pool
     * @return The address of the locker used to provide liquidity
     */
    function launch(LaunchParams calldata _params, address _recipient, address _refundAddress)
        external
        returns (PoolLauncherPool memory, address);

    /**
     * @notice The address of the pool factory for V2 pools
     * @return Address of the V2 pool factory
     */
    function v2Factory() external view returns (IV2Factory);

    /**
     * @notice The address of the router for V2 pools
     * @return Address of the V2 router
     */
    function v2Router() external view returns (address);

    /**
     * @notice Get the underlying pool for a given pair of tokens and stable param
     * @param _tokenA The address of the first token
     * @param _tokenB The address of the second token
     * @param _stable Whether the pool is stable or volatile
     * @return underlyingPool The address of the underlying pool
     */
    function getPool(address _tokenA, address _tokenB, bool _stable) external returns (address underlyingPool);
}
