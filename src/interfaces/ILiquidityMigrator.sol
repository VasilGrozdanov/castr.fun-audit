// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICLPool} from "@velodrome-finance/slipstream/core/interfaces/ICLPool.sol";
import {INonfungiblePositionManager} from "@velodrome-finance/slipstream/periphery/interfaces/INonfungiblePositionManager.sol";
import {ILiquidityLocker} from "src/interfaces/ILiquidityLocker.sol";

interface IWETH9 is IERC20 {
    function deposit() external payable;

    function withdraw(uint256 amount) external;
}

/**
 * @dev Interface for a Aerodrome Concentrated Liquidity migrator. It handles the creation of Aerodrome Concentrated Liquidity pools, adding liquidity, and locking liquidity in the UNCX liquidity locker.
 * This interface defines the functions and events related to creating pools,adding and locking liquidity.
 */
interface ILiquidityMigrator {
    struct Token {
        address tokenAddress;
        IERC20 instance;
        bool isWeth;
    }
    struct Pool {
        address poolAddress;
        ICLPool instance;
        Token token0;
        Token token1;
        uint256 amount0;
        uint256 amount1;
    }

    event PoolCreated(
        address indexed pool,
        address indexed token0,
        address indexed token1,
        int24 tick,
        uint256 timestamp,
        uint160 sqrtPriceX96
    );
    event LiquidityLocked(
        address indexed locker,
        uint256 tokenId,
        uint256 timestamp
    );
    event PoolMigrated(
        address indexed pool,
        address indexed token,
        uint256 tokenId,
        address locker,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        uint256 timestamp
    );

    error LiquidityMigrator__TransferFailed();
    error LiquidityMigrator__NotBondingCurve();

    /**
     * @dev The BondingCurveStorage contract is a central contract that holds all the bonding curves and related data.
     * @return The address of the BondingCurveStorage contract.
     */
    function getBondingCurveStorage() external view returns (address);

    /**
     * @dev The WETH address is used to wrap and unwrap Ether for liquidity operations.
     * @return The address of the WETH contract.
     */
    function getWethAddress() external view returns (address);

    /**
     * @dev The WETH contract is used to wrap and unwrap Ether for liquidity operations.
     * @return The WETH contract instance.
     */
    function getWeth() external view returns (IWETH9);

    /**
     * @dev The licquidity locker contract is used to lock liquidity and eventually migrate it to Aerodrome concentrated liquidity locker. See ICLLockerFactory for more details.
     * @return The address of the liquidity locker contract.
     */
    function getLiquidityLocker() external view returns (ILiquidityLocker);

    /**
     * @notice Creates a new Aerodrome Concentrated Liquidity pool for the specified token (token/WETH pair) and token amount.
     * @dev The pool is created with a fixed tick spacing, that is stored in this contract. Call tickSpacing() to get the current value (e.g. 2000 = 1%). 1% is the maximum fee tier supported. Check the Aerodrome Concentrated Liquidity Pool documentation for more details on fee tiers and tick spacing.
     * @dev This function can be called only by the bonding curve of the respective token.
     *
     * @param token The address of the token to be added in the pair.
     * @param amountToAdd The amount of the token to add to the pool.
     * @return tokenId The NFT ID of the created pool liquidity position.
     * @return liquidity The amount of liquidity for this position.
     * @return amount0 The amount of the first token added to the pool.
     * @return amount1 The amount of the second token added to the pool.
     * @return locker The Locker created for the liquidity (See ICLLocker for more details).
     */
    function createPoolAndLockLiquidity(
        address payable token,
        uint256 amountToAdd
    )
        external
        payable
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1,
            address locker
        );

    /**
     * @dev The FeeAccount contract is responsible for managing the fees collected from the Aerodrome Concentrated Liquidity pools and the bonding curves.
     * @return The address of the FeeAccount contract.
     */
    function getFeeAccount() external view returns (address);

    /**
     * @dev The NonfungiblePositionManager contract is used to manage the liquidity positions in Aerodrome Concentrated Liquidity pools.
     * @return The instance of the NonfungiblePositionManager contract.
     */
    function nonfungiblePositionManager()
        external
        view
        returns (INonfungiblePositionManager);
}
