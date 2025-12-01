// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IV2Pool} from "../../external/IV2Pool.sol";
import {IV2Router} from "../../external/IV2Router.sol";
import {IV2Factory} from "../../external/IV2Factory.sol";
import {IV2LockerFactory} from "../../interfaces/extensions/v2/IV2LockerFactory.sol";
import {IV2Locker} from "../../interfaces/extensions/v2/IV2Locker.sol";
import {ILockerFactory} from "../../interfaces/ILockerFactory.sol";
import {LockerFactory} from "../../LockerFactory.sol";

/// @title V2LockerFactory
/// @author velodrome.finance
/// @notice Manages creating locker instances
contract V2LockerFactory is LockerFactory, IV2LockerFactory {
    using SafeERC20 for IERC20;

    /// @inheritdoc IV2LockerFactory
    address public immutable v2Factory;
    /// @inheritdoc IV2LockerFactory
    address public immutable v2Router;

    constructor(
        address _owner,
        address _poolLauncher,
        address _lockerImplementation,
        address _v2Factory,
        address _v2Router,
        address _voter
    ) LockerFactory(_owner, _poolLauncher, _lockerImplementation, _voter, PoolType.BASIC) {
        v2Factory = _v2Factory;
        v2Router = _v2Router;
    }

    /// @inheritdoc IV2LockerFactory
    function lock(
        address _pool,
        uint256 _lp,
        uint32 _lockUntil,
        address _beneficiary,
        uint16 _beneficiaryShare,
        uint16 _bribeableShare,
        address _owner
    ) external nonReentrant returns (address) {
        if (uint256(_lockUntil) <= block.timestamp) revert InvalidLockTime();
        if (_beneficiary != address(0)) {
            if (_beneficiaryShare == 0 || _beneficiaryShare > MAX_BPS) revert InvalidBeneficiaryShare();
        }
        if (_bribeableShare > MAX_BPS) revert InvalidBribeableShare();
        if (!IV2Factory(v2Factory).isPool({pool: _pool})) revert PoolNotInFactory();

        address locker = Clones.clone({implementation: lockerImplementation});
        IV2Locker(locker).initialize({
            _owner: _owner,
            _pool: _pool,
            _lp: _lp,
            _lockedUntil: _lockUntil,
            _beneficiary: _beneficiary,
            _beneficiaryShare: _beneficiaryShare,
            _bribeableShare: _bribeableShare
        });

        _addLocker({_locker: locker, _pool: _pool, _lockerOwner: _owner});

        if (msg.sender != poolLauncher) {
            IERC20(_pool).safeTransferFrom({from: msg.sender, to: locker, value: _lp});
        } else {
            IERC20(_pool).safeTransfer({to: locker, value: _lp});
        }

        emit LockCreated({
            owner: _owner,
            locker: locker,
            lp: _lp,
            lockUntil: _lockUntil,
            beneficiary: _beneficiary,
            beneficiaryShare: _beneficiaryShare,
            bribeableShare: _bribeableShare
        });
        return locker;
    }

    /// @inheritdoc LockerFactory
    function migrate(
        address _locker,
        uint256 _unlock0Min,
        uint256 _unlock1Min,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external override(LockerFactory, ILockerFactory) nonReentrant returns (uint256, uint256, address) {
        if (_unlock0Min < _amount0Min) revert InsufficientUnlock0Min();
        if (_unlock1Min < _amount1Min) revert InsufficientUnlock1Min();
        if (newLockerFactory == address(0)) revert MigrationDisabled();
        if (!instances[_locker]) revert NotLocker();

        address pool = IV2Locker(_locker).pool();

        if (msg.sender != poolLauncher) {
            if (msg.sender != Ownable(_locker).owner()) revert NotLockerOwner();
            uint32 lockedUntil = IV2Locker(_locker).lockedUntil();
            if (lockedUntil <= block.timestamp) revert NotLocked();

            _unlockLP({
                _locker: _locker,
                _pool: pool,
                _recipient: pool,
                _refundAddress: address(this),
                _owner: msg.sender
            });

            (uint256 amount0, uint256 amount1, address newLocker) = _migrateLiquidity({
                _migrateParams: IV2LockerFactory.MigrationParams({
                    locker: _locker,
                    pool: pool,
                    lockedUntil: lockedUntil,
                    unlock0Min: _unlock0Min,
                    unlock1Min: _unlock1Min,
                    amount0Min: _amount0Min,
                    amount1Min: _amount1Min
                })
            });
            emit LockerMigrated({oldLocker: _locker, newLocker: newLocker, lp: IV2Locker(_locker).lp()});
            return (amount0, amount1, newLocker);
        } else {
            _unlockLP({
                _locker: _locker,
                _pool: pool,
                _recipient: pool,
                _refundAddress: poolLauncher,
                _owner: Ownable(_locker).owner()
            });
            (uint256 amount0, uint256 amount1) = IV2Pool(pool).burn({to: poolLauncher});
            if (amount0 < _unlock0Min) revert InsufficientAmount0Unlocked();
            if (amount1 < _unlock1Min) revert InsufficientAmount1Unlocked();
            return (amount0, amount1, address(0));
        }
    }

    /**
     * @notice Migrates the liquidity from the given locker into a new position on the new locker factory
     * @param _migrateParams Struct containing the parameters required to migrate liquidity
     * @return Tuple containing the amount of liquidity minted and the amounts of token0 and token1 unlocked
     */
    function _migrateLiquidity(IV2LockerFactory.MigrationParams memory _migrateParams)
        private
        returns (uint256, uint256, address)
    {
        bool stable = IV2Pool(_migrateParams.pool).stable();
        (address token0, address token1) = IV2Pool(_migrateParams.pool).tokens();
        (uint256 amount0Unlocked, uint256 amount1Unlocked, uint256 liquidity) =
            _migrateLP({_token0: token0, _token1: token1, _stable: stable, _migrateParams: _migrateParams});

        address _newLockerFactory = newLockerFactory;
        address newUnderlyingPool = IV2Factory(IV2LockerFactory(_newLockerFactory).v2Factory()).getPool({
            tokenA: token0,
            tokenB: token1,
            stable: stable
        });

        NewLockerParams memory newLockerParams = NewLockerParams({
            lockedUntil: _migrateParams.lockedUntil,
            beneficiary: IV2Locker(_migrateParams.locker).beneficiary(),
            beneficiaryShare: IV2Locker(_migrateParams.locker).beneficiaryShare(),
            bribeableShare: IV2Locker(_migrateParams.locker).bribeableShare()
        });

        IERC20(newUnderlyingPool).forceApprove({spender: _newLockerFactory, value: liquidity});
        address newLocker = IV2LockerFactory(_newLockerFactory).lock({
            _pool: newUnderlyingPool,
            _lp: liquidity,
            _lockUntil: newLockerParams.lockedUntil,
            _beneficiary: newLockerParams.beneficiary,
            _beneficiaryShare: newLockerParams.beneficiaryShare,
            _bribeableShare: newLockerParams.bribeableShare,
            _owner: msg.sender
        });

        /// @dev Refund leftovers to new locker
        uint256 amount0Refund = IERC20(token0).balanceOf({account: address(this)});
        uint256 amount1Refund = IERC20(token1).balanceOf({account: address(this)});
        if (amount0Refund > 0) IERC20(token0).safeTransfer({to: newLocker, value: amount0Refund});
        if (amount1Refund > 0) IERC20(token1).safeTransfer({to: newLocker, value: amount1Refund});

        return (amount0Unlocked, amount1Unlocked, newLocker);
    }

    /**
     * @notice Migrates an LP to the pool factory associated with the new locker factory
     * @param _token0 The first token of the pool
     * @param _token1 The second token of the pool
     * @param _stable Flag to signal whether the pool is stable or volatile
     * @param _migrateParams Struct containing the parameters required to migrate liquidity
     * @return The amount of token0 unlocked
     * @return The amount of token1 unlocked
     * @return The amount of new liquidity minted
     */
    function _migrateLP(
        address _token0,
        address _token1,
        bool _stable,
        IV2LockerFactory.MigrationParams memory _migrateParams
    ) internal returns (uint256, uint256, uint256) {
        address router = IV2LockerFactory(newLockerFactory).v2Router();
        (uint256 amount0, uint256 amount1) = IV2Pool(_migrateParams.pool).burn({to: address(this)});
        if (amount0 < _migrateParams.unlock0Min) revert InsufficientAmount0Unlocked();
        if (amount1 < _migrateParams.unlock1Min) revert InsufficientAmount1Unlocked();
        IERC20(_token0).forceApprove({spender: router, value: amount0});
        IERC20(_token1).forceApprove({spender: router, value: amount1});

        //slither-disable-next-line unused-return
        (,, uint256 liquidity) = IV2Router(router).addLiquidity({
            tokenA: _token0,
            tokenB: _token1,
            stable: _stable,
            amountADesired: amount0,
            amountBDesired: amount1,
            amountAMin: _migrateParams.amount0Min,
            amountBMin: _migrateParams.amount1Min,
            to: address(this),
            deadline: block.timestamp
        });

        IERC20(_token0).forceApprove({spender: router, value: 0});
        IERC20(_token1).forceApprove({spender: router, value: 0});

        return (amount0, amount1, liquidity);
    }

    function _liquidity(address _locker) internal view override returns (uint256) {
        return IV2Locker(_locker).lp();
    }
}
