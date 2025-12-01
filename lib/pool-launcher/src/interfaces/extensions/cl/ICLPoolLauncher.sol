// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager as INfpm} from "../../../external/INonfungiblePositionManager.sol";
import {ICLFactory} from "../../../external/ICLFactory.sol";
import {IPoolLauncher} from "../../IPoolLauncher.sol";

interface ICLPoolLauncher is IPoolLauncher {
    error InvalidSqrtPrice();

    struct LaunchParams {
        /// @notice address of the pool launcher token
        address poolLauncherToken;
        /// @notice address of the token to pair with
        address tokenToPair;
        /// @notice tickSpacing for the new pool
        int24 tickSpacing;
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
        /// @notice initial price for concentrated liquidity pools
        uint160 initialSqrtPriceX96;
        /// @notice lower tick for CL pools
        int24 tickLower;
        /// @notice upper tick for CL pools
        int24 tickUpper;
        /// @notice duration for which to lock the liquidity (0 = no lock, type(uint32).max = infinite lock)
        uint32 lockDuration;
    }

    struct MintParams {
        /// @notice first token of the pool, unsorted
        address tokenA;
        /// @notice second token of the pool, unsorted
        address tokenB;
        /// @notice tickSpacing of the pool
        int24 tickSpacing;
        /// @notice lower tick for the liquidity position
        int24 tickLower;
        /// @notice upper tick for the liquidity position
        int24 tickUpper;
        /// @notice amount of liquidity to be provided in the first token
        uint256 amountA;
        /// @notice amount of liquidity to be provided in the second token
        uint256 amountB;
        /// @notice minimum amount of liquidity to be provided in the first token
        uint256 amountAMin;
        /// @notice minimum amount of liquidity to be provided in the second token
        uint256 amountBMin;
        /// @notice address to which the liquidity should be minted
        address recipient;
    }

    struct PositionInfo {
        /// @notice address of the pool launcher token
        address poolLauncherToken;
        /// @notice address of the token to pair with
        address tokenToPair;
        /// @notice lower tick for the position
        int24 tickLower;
        /// @notice upper tick for the position
        int24 tickUpper;
        /// @notice tickSpacing of the pool
        int24 tickSpacing;
        /// @notice amount of `poolLauncherToken` locked in the position
        uint256 poolLauncherAmount;
        /// @notice amount of `tokenToPair` locked in the position
        uint256 tokenToPairAmount;
    }

    /**
     * @notice Launch a new pool launcher concentrated liquidity pool
     * @param _params launch parameters
     * @param _recipient address to receive the pool launcher pool nft
     * @return The newly created pool launcher pool
     * @return The address of the locker used to provide liquidity
     */
    function launch(LaunchParams calldata _params, address _recipient)
        external
        returns (PoolLauncherPool memory, address);

    /**
     * @notice The address of the NonfungiblePositionManager that manages CL liquidity positions
     * @return Address of the NonfungiblePositionManager
     */
    function nfpManager() external view returns (INfpm);

    /**
     * @notice The address of the pool factory for concentrated liquidity pools
     * @return Address of the CL pool factory
     */
    function clFactory() external view returns (ICLFactory);

    /**
     * @notice Get the underlying pool for a given pair of tokens and tickSpacing param
     * @param _tokenA The address of the first token
     * @param _tokenB The address of the second token
     * @param _tickSpacing The tick spacing for the pool
     * @return underlyingPool The address of the underlying pool
     */
    function getPool(address _tokenA, address _tokenB, int24 _tickSpacing) external returns (address underlyingPool);
}
