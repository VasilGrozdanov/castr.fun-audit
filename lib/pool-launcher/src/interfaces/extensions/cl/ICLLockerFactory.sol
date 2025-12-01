// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager as INfpm} from "../../../external/INonfungiblePositionManager.sol";
import {ICLFactory} from "../../../external/ICLFactory.sol";
import {ILockerFactory} from "../../ILockerFactory.sol";

interface ICLLockerFactory is ILockerFactory {
    struct MintParams {
        /// @notice token ID of the LP to be migrated
        uint256 oldLP;
        /// @notice address of the locker to be migrated
        address oldLocker;
        /// @notice unlock timestamp of the old locker
        uint32 lockedUntil;
        /// @notice amount of liquidity to be provided in token0
        uint256 amount0;
        /// @notice amount of liquidity to be provided in token1
        uint256 amount1;
        /// @notice minimum amount of liquidity to be provided in token0
        uint256 amount0Min;
        /// @notice minimum amount of liquidity to be provided in token1
        uint256 amount1Min;
    }

    struct MigrationParams {
        /// @notice token ID of the LP to be migrated
        uint256 oldLP;
        /// @notice locker to migrate the liquidity from
        address oldLocker;
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
     * @notice Creates a new locker instance
     * @param _lp The liquidity to lock
     * @param _lockUntil The timestamp until which the position should be locked
     * @param _beneficiary Optional address that will receive `_bribeableShare` of claimed fees/rewards
     * @param _beneficiaryShare The percentage of claimed fees/rewards that will be sent to the beneficiary (0-10000)
     * @param _bribeableShare The percentage of claimed fees/rewards that will be bribeable by external parties (0-10000)
     * @param _owner The owner of the locker
     * @return locker The created locker instance
     */
    function lock(
        uint256 _lp,
        uint32 _lockUntil,
        address _beneficiary,
        uint16 _beneficiaryShare,
        uint16 _bribeableShare,
        address _owner
    ) external returns (address);
}
