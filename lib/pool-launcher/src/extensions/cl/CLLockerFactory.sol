// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {ICLFactory} from "../../external/ICLFactory.sol";
import {INonfungiblePositionManager as INfpm} from "../../external/INonfungiblePositionManager.sol";
import {ICLLockerFactory} from "../../interfaces/extensions/cl/ICLLockerFactory.sol";
import {ICLLocker} from "../../interfaces/extensions/cl/ICLLocker.sol";
import {ILockerFactory} from "../../interfaces/ILockerFactory.sol";
import {LockerFactory} from "../../LockerFactory.sol";

/// @title CLLockerFactory
/// @author velodrome.finance
/// @notice LockerFactory extension that manages locker instances for CL positions.
contract CLLockerFactory is LockerFactory, ICLLockerFactory, IERC721Receiver {
    using SafeERC20 for IERC20;

    /// @inheritdoc ICLLockerFactory
    INfpm public immutable nfpManager;
    /// @inheritdoc ICLLockerFactory
    ICLFactory public immutable clFactory;

    constructor(
        address _owner,
        address _poolLauncher,
        address _lockerImplementation,
        address _nfpManager,
        address _voter
    ) LockerFactory(_owner, _poolLauncher, _lockerImplementation, _voter, PoolType.CONCENTRATED) {
        nfpManager = INfpm(_nfpManager);
        clFactory = INfpm(_nfpManager).factory();
    }

    /// @inheritdoc ICLLockerFactory
    function lock(
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

        address pool = _getPoolForPosition({_lp: _lp});
        address locker = Clones.clone({implementation: lockerImplementation});
        ICLLocker(locker).initialize({
            _owner: _owner,
            _pool: pool,
            _lp: _lp,
            _lockedUntil: _lockUntil,
            _beneficiary: _beneficiary,
            _beneficiaryShare: _beneficiaryShare,
            _bribeableShare: _bribeableShare
        });

        _addLocker({_locker: locker, _pool: pool, _lockerOwner: _owner});

        if (msg.sender != poolLauncher) {
            nfpManager.safeTransferFrom({from: msg.sender, to: locker, tokenId: _lp});
        } else {
            nfpManager.safeTransferFrom({from: address(this), to: address(locker), tokenId: _lp});
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

        /// @dev Unlock and migrate liquidity
        uint256 oldLP = ICLLocker(_locker).lp();
        uint32 lockedUntil = ICLLocker(_locker).lockedUntil();
        if (msg.sender == poolLauncher) {
            /// @dev Assumes the locker's `owner` and `lockedUntil` checks are handled by PoolLauncher
            (, uint256 amount0, uint256 amount1) = _migrateLiquidity({
                _migrateParams: ICLLockerFactory.MigrationParams({
                    oldLP: oldLP,
                    oldLocker: _locker,
                    lockedUntil: lockedUntil,
                    unlock0Min: _unlock0Min,
                    unlock1Min: _unlock1Min,
                    amount0Min: _amount0Min,
                    amount1Min: _amount1Min
                })
            });
            return (amount0, amount1, address(0));
        } else {
            if (msg.sender != Ownable(_locker).owner()) revert NotLockerOwnerOrPoolLauncher();
            if (block.timestamp >= lockedUntil) revert NotLocked();

            (address locker, uint256 amount0, uint256 amount1) = _migrateLiquidity({
                _migrateParams: ICLLockerFactory.MigrationParams({
                    oldLP: oldLP,
                    oldLocker: _locker,
                    lockedUntil: lockedUntil,
                    unlock0Min: _unlock0Min,
                    unlock1Min: _unlock1Min,
                    amount0Min: _amount0Min,
                    amount1Min: _amount1Min
                })
            });

            emit LockerMigrated({oldLocker: _locker, newLocker: locker, lp: oldLP});
            return (amount0, amount1, locker);
        }
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice Migrates the liquidity from the given locker into a new position on the new locker factory
     * @param _migrateParams Struct containing the parameters required to migrate liquidity
     * @return Tuple containing the locker for the new LP and the amounts of token0 and token1 unlocked
     */
    function _migrateLiquidity(ICLLockerFactory.MigrationParams memory _migrateParams)
        internal
        returns (address, uint256, uint256)
    {
        //slither-disable-next-line unused-return
        (,,,,,,, uint128 liquidity,,,,) = nfpManager.positions({tokenId: _migrateParams.oldLP});

        /// @dev Unlock liquidity
        address recipient = msg.sender != poolLauncher ? address(this) : poolLauncher;
        _unlockLP({
            _locker: _migrateParams.oldLocker,
            _pool: ICLLocker(_migrateParams.oldLocker).pool(),
            _recipient: address(this),
            _refundAddress: recipient,
            _owner: Ownable(_migrateParams.oldLocker).owner()
        });

        /// @dev Withdraw liquidity
        //slither-disable-next-line unused-return
        nfpManager.decreaseLiquidity(
            INfpm.DecreaseLiquidityParams({
                tokenId: _migrateParams.oldLP,
                liquidity: liquidity,
                amount0Min: _migrateParams.unlock0Min,
                amount1Min: _migrateParams.unlock1Min,
                deadline: block.timestamp
            })
        );
        (uint256 amount0, uint256 amount1) = nfpManager.collect(
            INfpm.CollectParams({
                tokenId: _migrateParams.oldLP,
                recipient: recipient,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        /// @dev Mint and migrate new liquidity position if not called by the poolLauncher
        //slither-disable-next-line uninitialized-local
        address newLocker;
        if (msg.sender != poolLauncher) {
            newLocker = _mintLP({
                _mintParams: ICLLockerFactory.MintParams({
                    oldLP: _migrateParams.oldLP,
                    oldLocker: _migrateParams.oldLocker,
                    lockedUntil: _migrateParams.lockedUntil,
                    amount0: amount0,
                    amount1: amount1,
                    amount0Min: _migrateParams.amount0Min,
                    amount1Min: _migrateParams.amount1Min
                })
            });
        }

        nfpManager.burn({tokenId: _migrateParams.oldLP});
        return (newLocker, amount0, amount1);
    }

    /**
     * @notice Mints a new liquidity position on the specified pool for the new locker factory.
     * @dev Assumes the amounts provided are sorted by token address
     * @param _mintParams Struct containing the parameters required to mint a liquidity position
     * @return The address of the new locker created
     */
    function _mintLP(ICLLockerFactory.MintParams memory _mintParams) private returns (address) {
        //slither-disable-next-line unused-return
        (,, address token0, address token1, int24 tickSpacing, int24 tickLower, int24 tickUpper,,,,,) =
            nfpManager.positions({tokenId: _mintParams.oldLP});

        INfpm newNfpManager = ICLLockerFactory(newLockerFactory).nfpManager();
        IERC20(token0).forceApprove({spender: address(newNfpManager), value: _mintParams.amount0});
        IERC20(token1).forceApprove({spender: address(newNfpManager), value: _mintParams.amount1});

        //slither-disable-next-line unused-return
        (uint256 lp,,,) = newNfpManager.mint({
            params: INfpm.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: tickSpacing,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: _mintParams.amount0,
                amount1Desired: _mintParams.amount1,
                amount0Min: _mintParams.amount0Min,
                amount1Min: _mintParams.amount1Min,
                recipient: address(this),
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        });

        /// @dev Migrate LP to new locker factory
        address locker = _migrateLP({
            _oldLocker: _mintParams.oldLocker,
            _lp: lp,
            _lockedUntil: _mintParams.lockedUntil,
            _token0: token0,
            _token1: token1
        });
        return locker;
    }

    /**
     * @notice Migrates an LP to the new locker factory
     * @param _oldLocker The locker to migrate the position from
     * @param _lp The token ID of the LP to be migrated
     * @param _lockedUntil The unlock timestamp of the old locker
     * @param _token0 The first token of the pool
     * @param _token1 The second token of the pool
     * @return The address of the new locker minted
     */
    function _migrateLP(address _oldLocker, uint256 _lp, uint32 _lockedUntil, address _token0, address _token1)
        private
        returns (address)
    {
        address _newLockerFactory = newLockerFactory;
        INfpm newNfpManager = ICLLockerFactory(_newLockerFactory).nfpManager();

        newNfpManager.approve({to: _newLockerFactory, tokenId: _lp});
        address newLocker = ICLLockerFactory(_newLockerFactory).lock({
            _lp: _lp,
            _lockUntil: _lockedUntil,
            _beneficiary: ICLLocker(_oldLocker).beneficiary(),
            _beneficiaryShare: ICLLocker(_oldLocker).beneficiaryShare(),
            _bribeableShare: ICLLocker(_oldLocker).bribeableShare(),
            _owner: msg.sender
        });
        /// @dev Refund leftovers and reset allowances
        _refundLeftover({_token: _token0, _recipient: newLocker, _spender: address(newNfpManager)});
        _refundLeftover({_token: _token1, _recipient: newLocker, _spender: address(newNfpManager)});

        return newLocker;
    }

    /**
     * @notice Refunds any leftover tokens to a recipient and resets the allowance
     * @dev Should be used after minting a new liquidity position
     * @param _token The address of the token to refund
     * @param _recipient The recipient for the refund
     * @param _spender The address of the spender to reset allowance for
     */
    function _refundLeftover(address _token, address _recipient, address _spender) private {
        uint256 leftover = IERC20(_token).balanceOf({account: address(this)});
        if (leftover > 0) {
            IERC20(_token).safeTransfer({to: _recipient, value: leftover});
            IERC20(_token).forceApprove({spender: _spender, value: 0});
        }
    }

    /**
     * @notice Fetches the pool address for a given LP
     * @param _lp The position's token ID
     * @return The address of the underlying pool
     */
    function _getPoolForPosition(uint256 _lp) internal view returns (address) {
        //slither-disable-next-line unused-return
        (,, address token0, address token1, int24 tickSpacing,,,,,,,) = nfpManager.positions({tokenId: _lp});

        return clFactory.getPool({tokenA: token0, tokenB: token1, tickSpacing: tickSpacing});
    }

    function _liquidity(address _locker) internal view override returns (uint256) {
        //slither-disable-next-line unused-return
        (,,,,,,, uint128 liquidity,,,,) = nfpManager.positions({tokenId: ICLLocker(_locker).lp()});
        return liquidity;
    }
}
