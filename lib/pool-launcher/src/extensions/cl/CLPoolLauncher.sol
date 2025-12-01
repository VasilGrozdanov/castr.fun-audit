// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ICLPool} from "../../external/ICLPool.sol";
import {ICLFactory} from "../../external/ICLFactory.sol";
import {INonfungiblePositionManager as INfpm} from "../../external/INonfungiblePositionManager.sol";
import {ICLLocker} from "../../interfaces/extensions/cl/ICLLocker.sol";
import {ICLLockerFactory} from "../../interfaces/extensions/cl/ICLLockerFactory.sol";
import {ICLPoolLauncher} from "../../interfaces/extensions/cl/ICLPoolLauncher.sol";
import {IPoolLauncher} from "../../interfaces/IPoolLauncher.sol";
import {PoolLauncher} from "../../PoolLauncher.sol";

import {TickMath} from "../../libraries/TickMath.sol";

/// @title CLPoolLauncher
/// @author velodrome.finance
/// @notice Pool launcher extension used to launch concentrated liquidity pools.
contract CLPoolLauncher is PoolLauncher, ICLPoolLauncher {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @inheritdoc ICLPoolLauncher
    INfpm public immutable nfpManager;
    /// @inheritdoc ICLPoolLauncher
    ICLFactory public immutable clFactory;

    /// @inheritdoc ICLPoolLauncher
    mapping(address _tokenA => mapping(address _tokenB => mapping(int24 _tickSpacing => address underlyingPool))) public
        getPool;

    constructor(address _owner, address _nfpManager, address _lockerFactory) PoolLauncher(_owner, _lockerFactory) {
        nfpManager = INfpm(_nfpManager);
        clFactory = INfpm(_nfpManager).factory();
    }

    /// @inheritdoc ICLPoolLauncher
    function launch(LaunchParams calldata _params, address _recipient)
        external
        nonReentrant
        returns (PoolLauncherPool memory, address)
    {
        address poolLauncherToken = _params.poolLauncherToken;
        if (_pairableTokens.contains({value: poolLauncherToken})) revert InvalidPoolLauncherToken();
        address tokenToPair = _params.tokenToPair;

        if (getPool[poolLauncherToken][tokenToPair][_params.tickSpacing] != address(0)) revert PoolAlreadyExists();
        if (!_pairableTokens.contains(tokenToPair)) revert InvalidToken();

        int24 tick = TickMath.getTickAtSqrtRatio({sqrtPriceX96: _params.liquidity.initialSqrtPriceX96});
        if (tick < _params.liquidity.tickLower || tick > _params.liquidity.tickUpper) {
            revert InvalidSqrtPrice();
        }

        address underlyingPool =
            clFactory.getPool({tokenA: poolLauncherToken, tokenB: tokenToPair, tickSpacing: _params.tickSpacing});
        if (underlyingPool == address(0)) {
            underlyingPool = clFactory.createPool({
                tokenA: poolLauncherToken,
                tokenB: tokenToPair,
                tickSpacing: _params.tickSpacing,
                sqrtPriceX96: _params.liquidity.initialSqrtPriceX96
            });
        }

        //slither-disable-next-line uninitialized-local
        address locker;
        if (_params.liquidity.lockDuration == 0) {
            _mintLP({
                _mintParams: ICLPoolLauncher.MintParams({
                    tokenA: poolLauncherToken,
                    tokenB: tokenToPair,
                    tickSpacing: _params.tickSpacing,
                    tickLower: _params.liquidity.tickLower,
                    tickUpper: _params.liquidity.tickUpper,
                    amountA: _params.liquidity.amountPoolLauncherToken,
                    amountB: _params.liquidity.amountTokenToPair,
                    amountAMin: _params.liquidity.amountPoolLauncherTokenMin,
                    amountBMin: _params.liquidity.amountTokenToPairMin,
                    recipient: _recipient
                })
            });
        } else {
            uint256 lp = _mintLP({
                _mintParams: ICLPoolLauncher.MintParams({
                    tokenA: poolLauncherToken,
                    tokenB: tokenToPair,
                    tickSpacing: _params.tickSpacing,
                    tickLower: _params.liquidity.tickLower,
                    tickUpper: _params.liquidity.tickUpper,
                    amountA: _params.liquidity.amountPoolLauncherToken,
                    amountB: _params.liquidity.amountTokenToPair,
                    amountAMin: _params.liquidity.amountPoolLauncherTokenMin,
                    amountBMin: _params.liquidity.amountTokenToPairMin,
                    recipient: lockerFactory
                })
            });

            // Lock liquidity
            locker = ICLLockerFactory(lockerFactory).lock({
                _lp: lp,
                _lockUntil: _params.liquidity.lockDuration == type(uint32).max
                    ? type(uint32).max
                    : uint32(block.timestamp + _params.liquidity.lockDuration),
                _beneficiary: address(0),
                _beneficiaryShare: 0,
                _bribeableShare: 500, // 5%
                _owner: _recipient
            });
        }

        PoolLauncherPool memory pool = PoolLauncherPool({
            createdAt: uint32(block.timestamp),
            pool: underlyingPool,
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair
        });
        //slither-disable-next-line reentrancy-no-eth
        getPool[poolLauncherToken][tokenToPair][_params.tickSpacing] = underlyingPool;
        getPool[tokenToPair][poolLauncherToken][_params.tickSpacing] = underlyingPool;
        _pools[underlyingPool] = pool;

        emit Launch({
            poolLauncherToken: poolLauncherToken,
            pool: underlyingPool,
            sender: msg.sender,
            poolLauncherPool: pool
        });
        return (pool, locker);
    }

    /// @inheritdoc PoolLauncher
    function migrate(
        address _locker,
        uint256 _poolLauncherUnlockMin,
        uint256 _tokenToPairUnlockMin,
        uint256 _poolLauncherAmountMin,
        uint256 _tokenToPairAmountMin
    ) external override(PoolLauncher, IPoolLauncher) nonReentrant returns (PoolLauncherPool memory, address) {
        if (_poolLauncherUnlockMin < _poolLauncherAmountMin) revert InsufficientPoolLauncherUnlockMin();
        if (_tokenToPairUnlockMin < _tokenToPairAmountMin) revert InsufficientTokenToPairUnlockMin();

        address _newPoolLauncher = newPoolLauncher;
        if (_newPoolLauncher == address(0)) revert NewPoolLauncherNotSet();

        address lockerOwner = Ownable(_locker).owner();
        if (msg.sender != lockerOwner) revert NotLockerOwner();

        uint256 lockedUntil = ICLLocker(_locker).lockedUntil();
        if (block.timestamp >= lockedUntil) revert NotLocked();

        /// @dev Unlock liquidity and fetch position info
        address underlyingPool = ICLLocker(_locker).pool();
        ICLPoolLauncher.PositionInfo memory positionInfo = _migratePosition({
            _locker: _locker,
            _underlyingPool: underlyingPool,
            _poolLauncherUnlockMin: _poolLauncherUnlockMin,
            _tokenToPairUnlockMin: _tokenToPairUnlockMin,
            _poolLauncherAmountMin: _poolLauncherAmountMin,
            _tokenToPairAmountMin: _tokenToPairAmountMin
        });

        IERC20(positionInfo.poolLauncherToken).forceApprove({
            spender: _newPoolLauncher,
            value: positionInfo.poolLauncherAmount
        });
        IERC20(positionInfo.tokenToPair).forceApprove({spender: _newPoolLauncher, value: positionInfo.tokenToPairAmount});

        /// @dev Launch pool on new Pool Launcher
        //slither-disable-next-line unused-return
        (uint160 sqrtPrice,,,,,) = ICLPool(underlyingPool).slot0();
        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: positionInfo.poolLauncherToken,
            tokenToPair: positionInfo.tokenToPair,
            tickSpacing: positionInfo.tickSpacing,
            liquidity: ICLPoolLauncher.LiquidityParams({
                amountPoolLauncherToken: positionInfo.poolLauncherAmount,
                amountTokenToPair: positionInfo.tokenToPairAmount,
                amountPoolLauncherTokenMin: _poolLauncherAmountMin,
                amountTokenToPairMin: _tokenToPairAmountMin,
                initialSqrtPriceX96: sqrtPrice,
                tickLower: positionInfo.tickLower,
                tickUpper: positionInfo.tickUpper,
                lockDuration: lockedUntil == type(uint32).max ? type(uint32).max : uint32(lockedUntil - block.timestamp)
            })
        });

        (IPoolLauncher.PoolLauncherPool memory newPool, address newLocker) =
            CLPoolLauncher(newPoolLauncher).launch({_params: launchParams, _recipient: lockerOwner});

        /// @dev Transfer leftovers to new locker
        _refundLeftover({_token: positionInfo.poolLauncherToken, _recipient: newLocker});
        _refundLeftover({_token: positionInfo.tokenToPair, _recipient: newLocker});

        emit Migrate({
            underlyingPool: underlyingPool,
            locker: _locker,
            newPoolLauncherPool: newPool,
            newLocker: newLocker
        });
        return (newPool, newLocker);
    }

    /**
     * @notice Mints a new liquidity position on the specified pool for a given recipient.
     * @param _mintParams Struct containing the parameters required to mint a liquidity position
     * @return The token ID of the minted liquidity position
     */
    function _mintLP(ICLPoolLauncher.MintParams memory _mintParams) private returns (uint256) {
        (address token0, address token1) = _mintParams.tokenA < _mintParams.tokenB
            ? (_mintParams.tokenA, _mintParams.tokenB)
            : (_mintParams.tokenB, _mintParams.tokenA);
        (uint256 amount0, uint256 amount1, uint256 amount0Min, uint256 amount1Min) = _mintParams.tokenA == token0
            ? (_mintParams.amountA, _mintParams.amountB, _mintParams.amountAMin, _mintParams.amountBMin)
            : (_mintParams.amountB, _mintParams.amountA, _mintParams.amountBMin, _mintParams.amountAMin);

        IERC20(token0).safeTransferFrom({from: msg.sender, to: address(this), value: amount0});
        IERC20(token1).safeTransferFrom({from: msg.sender, to: address(this), value: amount1});

        IERC20(token0).safeIncreaseAllowance({spender: address(nfpManager), value: amount0});
        IERC20(token1).safeIncreaseAllowance({spender: address(nfpManager), value: amount1});

        //slither-disable-next-line unused-return
        (uint256 lp,,,) = nfpManager.mint({
            params: INfpm.MintParams({
                token0: token0,
                token1: token1,
                tickSpacing: _mintParams.tickSpacing,
                tickLower: _mintParams.tickLower,
                tickUpper: _mintParams.tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: amount0Min,
                amount1Min: amount1Min,
                recipient: _mintParams.recipient,
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        });

        uint256 leftover = IERC20(token0).balanceOf({account: address(this)});
        if (leftover > 0) {
            IERC20(token0).safeTransfer({to: msg.sender, value: leftover});
            IERC20(token0).forceApprove({spender: address(nfpManager), value: 0});
        }

        leftover = IERC20(token1).balanceOf({account: address(this)});
        if (leftover > 0) {
            IERC20(token1).safeTransfer({to: msg.sender, value: leftover});
            IERC20(token1).forceApprove({spender: address(nfpManager), value: 0});
        }

        return lp;
    }

    /**
     * @notice Migrates a locker position via the locker factory
     * @dev Reverts if the underlying pool is not registered in the pool launcher
     * @param _locker The locker to be migrated
     * @param _underlyingPool The underlying pool for the locker
     * @param _poolLauncherUnlockMin Minimum amount of pool launcher token to unlock from the old LP
     * @param _tokenToPairUnlockMin Minimum amount of token to pair to unlock from the old LP
     * @param _poolLauncherAmountMin Minimum amount of pool launcher token to migrate
     * @param _tokenToPairAmountMin Minimum amount of token to pair to migrate
     * @return Struct containing the LP info for the locker
     */
    function _migratePosition(
        address _locker,
        address _underlyingPool,
        uint256 _poolLauncherUnlockMin,
        uint256 _tokenToPairUnlockMin,
        uint256 _poolLauncherAmountMin,
        uint256 _tokenToPairAmountMin
    ) internal returns (ICLPoolLauncher.PositionInfo memory) {
        address poolLauncherToken = _pools[_underlyingPool].poolLauncherToken;
        if (poolLauncherToken == address(0)) revert PoolNotInPoolLauncher();

        //slither-disable-next-line uninitialized-local
        ICLPoolLauncher.PositionInfo memory positionInfo;
        address token0;
        address token1;
        //slither-disable-next-line unused-return
        (,, token0, token1, positionInfo.tickSpacing, positionInfo.tickLower, positionInfo.tickUpper,,,,,) =
            INfpm(nfpManager).positions({tokenId: ICLLocker(_locker).lp()});

        /// @dev Unlock liquidity for Pool Launcher, sort tokens and amounts
        if (poolLauncherToken == token0) {
            //slither-disable-next-line unused-return
            (positionInfo.poolLauncherAmount, positionInfo.tokenToPairAmount,) = ICLLockerFactory(lockerFactory).migrate({
                _locker: _locker,
                _unlock0Min: _poolLauncherUnlockMin,
                _unlock1Min: _tokenToPairUnlockMin,
                _amount0Min: _poolLauncherAmountMin,
                _amount1Min: _tokenToPairAmountMin
            });

            (positionInfo.poolLauncherToken, positionInfo.tokenToPair) = (token0, token1);
        } else {
            //slither-disable-next-line unused-return
            (positionInfo.tokenToPairAmount, positionInfo.poolLauncherAmount,) = ICLLockerFactory(lockerFactory).migrate({
                _locker: _locker,
                _unlock0Min: _tokenToPairUnlockMin,
                _unlock1Min: _poolLauncherUnlockMin,
                _amount0Min: _tokenToPairAmountMin,
                _amount1Min: _poolLauncherAmountMin
            });

            (positionInfo.poolLauncherToken, positionInfo.tokenToPair) = (token1, token0);
        }

        return positionInfo;
    }
}
