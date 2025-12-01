// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILockerFactory} from "../../ILockerFactory.sol";

interface IV2LockerFactory is ILockerFactory {
    /// @dev Struct to avoid "stack too deep" errors in migrate
    struct NewLockerParams {
        uint32 lockedUntil;
        address beneficiary;
        uint16 beneficiaryShare;
        uint16 bribeableShare;
    }

    struct MigrationParams {
        /// @notice locker to migrate the liquidity from
        address locker;
        /// @notice address of the pool from which the liquidity should be migrated
        address pool;
        /// @notice unlock timestamp for the new locker
        uint32 lockedUntil;
        /// @notice minimum amount of token0 to unlock from the old LP
        uint256 unlock0Min;
        /// @notice minimum amount of token1 to unlock from the old LP
        uint256 unlock1Min;
        /// @notice minimum amount of token0 to migrate to the new LP
        uint256 amount0Min;
        /// @notice minimum amount of token1 to migrate to the new LP
        uint256 amount1Min;
    }

    error PoolNotInFactory();
    error InsufficientAmount0Unlocked();
    error InsufficientAmount1Unlocked();

    /**
     * @notice The address of the pool factory for V2 pools
     * @return Address of the V2 pool factory
     */
    function v2Factory() external view returns (address);

    /**
     * @notice The address of the router for V2 pools
     * @return Address of the V2 router
     */
    function v2Router() external view returns (address);

    /**
     * @notice Creates a new locker instance
     * @param _pool The underlying pool of the position to lock
     * @param _lp The liquidity to lock
     * @param _lockUntil The timestamp until which the position should be locked
     * @param _beneficiary Optional address that will receive `_bribeableShare` of claimed fees/rewards
     * @param _beneficiaryShare The percentage of claimed fees/rewards that will be sent to the beneficiary (0-10000)
     * @param _bribeableShare The percentage of claimed fees/rewards that will be bribeable by external parties (0-10000)
     * @param _owner The owner of the locker
     * @return locker The created locker instance
     */
    function lock(
        address _pool,
        uint256 _lp,
        uint32 _lockUntil,
        address _beneficiary,
        uint16 _beneficiaryShare,
        uint16 _bribeableShare,
        address _owner
    ) external returns (address);
}
