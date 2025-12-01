// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IV2Pool} from "../../external/IV2Pool.sol";
import {IV2Router} from "../../external/IV2Router.sol";
import {IV2Factory} from "../../external/IV2Factory.sol";
import {ILocker} from "../../interfaces/ILocker.sol";
import {IV2LockerFactory} from "../../interfaces/extensions/v2/IV2LockerFactory.sol";
import {IV2PoolLauncher} from "../../interfaces/extensions/v2/IV2PoolLauncher.sol";
import {IPoolLauncher} from "../../interfaces/IPoolLauncher.sol";
import {PoolLauncher} from "../../PoolLauncher.sol";

/// @title V2PoolLauncher
/// @author velodrome.finance
/// @notice PoolLauncher extension used to launch V2 pools.
contract V2PoolLauncher is PoolLauncher, IV2PoolLauncher {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @inheritdoc IV2PoolLauncher
    IV2Factory public immutable v2Factory;
    /// @inheritdoc IV2PoolLauncher
    address public immutable v2Router;

    /// @inheritdoc IV2PoolLauncher
    mapping(address _tokenA => mapping(address _tokenB => mapping(bool _stable => address underlyingPool))) public
        getPool;

    constructor(address _owner, address _v2Factory, address _v2Router, address _lockerFactory)
        PoolLauncher(_owner, _lockerFactory)
    {
        v2Factory = IV2Factory(_v2Factory);
        v2Router = _v2Router;
    }

    /// @inheritdoc IV2PoolLauncher
    function launch(LaunchParams calldata _params, address _recipient, address _refundAddress)
        external
        nonReentrant
        returns (PoolLauncherPool memory, address)
    {
        address poolLauncherToken = _params.poolLauncherToken;
        if (_pairableTokens.contains({value: poolLauncherToken})) revert InvalidPoolLauncherToken();
        address tokenToPair = _params.tokenToPair;

        if (getPool[poolLauncherToken][tokenToPair][_params.stable] != address(0)) revert PoolAlreadyExists();
        if (!_pairableTokens.contains({value: tokenToPair})) revert InvalidToken();
        if (_refundAddress == address(0)) revert InvalidRefundAddress();

        IERC20(poolLauncherToken).safeTransferFrom({
            from: msg.sender,
            to: address(this),
            value: _params.liquidity.amountPoolLauncherToken
        });
        IERC20(tokenToPair).safeTransferFrom({
            from: msg.sender,
            to: address(this),
            value: _params.liquidity.amountTokenToPair
        });

        // slither-disable-next-line uninitialized-local
        address locker;
        if (_params.liquidity.lockDuration == 0) {
            // Return liquidity to the recipient directly
            //slither-disable-next-line unused-return
            _mintLP({
                _tokenA: poolLauncherToken,
                _tokenB: tokenToPair,
                _stable: _params.stable,
                _amountA: _params.liquidity.amountPoolLauncherToken,
                _amountB: _params.liquidity.amountTokenToPair,
                _amountAMin: _params.liquidity.amountPoolLauncherTokenMin,
                _amountBMin: _params.liquidity.amountTokenToPairMin,
                _recipient: _recipient
            });
        } else {
            uint256 liquidity = _mintLP({
                _tokenA: poolLauncherToken,
                _tokenB: tokenToPair,
                _stable: _params.stable,
                _amountA: _params.liquidity.amountPoolLauncherToken,
                _amountB: _params.liquidity.amountTokenToPair,
                _amountAMin: _params.liquidity.amountPoolLauncherTokenMin,
                _amountBMin: _params.liquidity.amountTokenToPairMin,
                _recipient: lockerFactory
            });

            // Lock liquidity
            locker = IV2LockerFactory(lockerFactory).lock({
                _pool: v2Factory.getPool({tokenA: poolLauncherToken, tokenB: tokenToPair, stable: _params.stable}),
                _lp: liquidity,
                _lockUntil: _params.liquidity.lockDuration == type(uint32).max
                    ? type(uint32).max
                    : uint32(block.timestamp + _params.liquidity.lockDuration),
                _beneficiary: address(0),
                _beneficiaryShare: 0,
                _bribeableShare: 500, // 5%
                _owner: _recipient
            });
        }
        /// @dev Refund leftovers to new locker
        _refundLeftover({_token: poolLauncherToken, _recipient: _refundAddress});
        _refundLeftover({_token: tokenToPair, _recipient: _refundAddress});

        address underlyingPool =
            v2Factory.getPool({tokenA: poolLauncherToken, tokenB: tokenToPair, stable: _params.stable});
        PoolLauncherPool memory pool = PoolLauncherPool({
            createdAt: uint32(block.timestamp),
            pool: underlyingPool,
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair
        });
        //slither-disable-next-line reentrancy-no-eth
        getPool[poolLauncherToken][tokenToPair][_params.stable] = underlyingPool;
        getPool[tokenToPair][poolLauncherToken][_params.stable] = underlyingPool;
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

        if (_locker == address(0)) revert InvalidLocker();
        address _newPoolLauncher = newPoolLauncher;
        if (_newPoolLauncher == address(0)) revert NewPoolLauncherNotSet();
        if (msg.sender != Ownable(_locker).owner()) revert NotLockerOwner();
        uint256 lockedUntil = ILocker(_locker).lockedUntil();
        if (lockedUntil <= block.timestamp) revert NotLocked();

        address underlyingPool = ILocker(_locker).pool();
        PoolLauncherPool memory pool = _pools[underlyingPool];
        if (pool.poolLauncherToken == address(0)) revert PoolNotInPoolLauncher();

        uint256 amountPoolLauncherToken;
        uint256 amountTokenToPair;
        /// @dev Sort amounts
        if (pool.poolLauncherToken < pool.tokenToPair) {
            //slither-disable-next-line unused-return
            (amountPoolLauncherToken, amountTokenToPair,) = IV2LockerFactory(lockerFactory).migrate({
                _locker: _locker,
                _unlock0Min: _poolLauncherUnlockMin,
                _unlock1Min: _tokenToPairUnlockMin,
                _amount0Min: _poolLauncherAmountMin,
                _amount1Min: _tokenToPairAmountMin
            });
        } else {
            //slither-disable-next-line unused-return
            (amountTokenToPair, amountPoolLauncherToken,) = IV2LockerFactory(lockerFactory).migrate({
                _locker: _locker,
                _unlock0Min: _tokenToPairUnlockMin,
                _unlock1Min: _poolLauncherUnlockMin,
                _amount0Min: _tokenToPairAmountMin,
                _amount1Min: _poolLauncherAmountMin
            });
        }

        IERC20(pool.poolLauncherToken).safeIncreaseAllowance({spender: _newPoolLauncher, value: amountPoolLauncherToken});
        IERC20(pool.tokenToPair).safeIncreaseAllowance({spender: _newPoolLauncher, value: amountTokenToPair});

        LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: pool.poolLauncherToken,
            tokenToPair: pool.tokenToPair,
            stable: IV2Pool(underlyingPool).stable(),
            liquidity: IV2PoolLauncher.LiquidityParams({
                amountPoolLauncherToken: amountPoolLauncherToken,
                amountTokenToPair: amountTokenToPair,
                amountPoolLauncherTokenMin: _poolLauncherAmountMin,
                amountTokenToPairMin: _tokenToPairAmountMin,
                lockDuration: lockedUntil == type(uint32).max ? type(uint32).max : uint32(lockedUntil - block.timestamp)
            })
        });

        (PoolLauncherPool memory newPoolLauncherPool, address newLocker) = IV2PoolLauncher(_newPoolLauncher).launch({
            _params: params,
            _recipient: msg.sender,
            _refundAddress: address(this)
        });

        /// @dev Transfer leftovers to new locker
        _refundLeftover({_token: pool.poolLauncherToken, _recipient: newLocker});
        _refundLeftover({_token: pool.tokenToPair, _recipient: newLocker});

        emit Migrate({
            underlyingPool: underlyingPool,
            locker: _locker,
            newPoolLauncherPool: newPoolLauncherPool,
            newLocker: newLocker
        });
        return (newPoolLauncherPool, newLocker);
    }

    /**
     * @notice Mints a new liquidity position on the specified pool for a given recipient.
     * @dev    Automatically creates the pool if it does not exist
     * @param _tokenA The first token of the pool, unsorted
     * @param _tokenB The second token of the pool, unsorted
     * @param _stable Whether the pool is stable or volatile
     * @param _amountA The amount of liquidity to be provided in the first token
     * @param _amountB The amount of liquidity to be provided in the second token
     * @param _amountAMin The minimum amount of liquidity to be provided in the first token
     * @param _amountBMin The minimum amount of liquidity to be provided in the second token
     * @param _recipient The recipient to which the liquidity should be minted
     * @return The amount of liquidity minted
     */
    function _mintLP(
        address _tokenA,
        address _tokenB,
        bool _stable,
        uint256 _amountA,
        uint256 _amountB,
        uint256 _amountAMin,
        uint256 _amountBMin,
        address _recipient
    ) internal returns (uint256) {
        IERC20(_tokenA).forceApprove({spender: v2Router, value: _amountA});
        IERC20(_tokenB).forceApprove({spender: v2Router, value: _amountB});

        //slither-disable-next-line unused-return
        (,, uint256 liquidity) = IV2Router(v2Router).addLiquidity({
            tokenA: _tokenA,
            tokenB: _tokenB,
            stable: _stable,
            amountADesired: _amountA,
            amountBDesired: _amountB,
            amountAMin: _amountAMin,
            amountBMin: _amountBMin,
            to: _recipient,
            deadline: block.timestamp
        });

        IERC20(_tokenA).forceApprove({spender: v2Router, value: 0});
        IERC20(_tokenB).forceApprove({spender: v2Router, value: 0});

        return liquidity;
    }
}
