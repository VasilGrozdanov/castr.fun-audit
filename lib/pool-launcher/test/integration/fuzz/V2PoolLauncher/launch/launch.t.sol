// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2PoolLauncher.t.sol";

contract LaunchUnitFuzzTest is V2PoolLauncherTest {
    // function testFuzz_WhenThePoolHasAlreadyBeenCreated(bool _stable, uint32 _lockDuration) external {
    //     // It should revert with {PoolAlreadyExists}
    //     uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
    //     uint256 _amountTokenToPair = 1000 * USDC_1;
    //     address _poolLauncherToken = address(token);
    //     address _tokenToPair = address(usdc);
    //
    //     IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
    //         amountPoolLauncherToken: _amountPoolLauncherToken,
    //         amountTokenToPair: _amountTokenToPair,
    //         lockDuration: _lockDuration
    //     });
    //     IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
    //         poolLauncherToken: _poolLauncherToken,
    //         tokenToPair: _tokenToPair,
    //         stable: _stable,
    //         liquidity: liquidityParams
    //     });
    //     deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
    //     deal(_tokenToPair, users.alice, _amountTokenToPair);
    //
    //     vm.startPrank(users.alice);
    //     token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
    //     usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
    //     v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
    //     vm.stopPrank();
    //
    //     vm.startPrank(users.charlie);
    //     vm.expectRevert(IPoolLauncher.PoolAlreadyExists.selector);
    //     v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
    // }

    modifier whenThePoolHasNotBeenCreatedYet() {
        _;
    }

    function testFuzz_WhenTheTokenToPairIsNotWhitelisted(address _tokenToPair, bool _stable, uint32 _lockDuration)
        external
        whenThePoolHasNotBeenCreatedYet
    {
        // It should revert with {InvalidToken}
        vm.assume(!v2PoolLauncher.isPairableToken({_token: _tokenToPair}));
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: _lockDuration
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: _stable,
            liquidity: liquidityParams
        });

        vm.startPrank(users.charlie);
        vm.expectRevert(IPoolLauncher.InvalidToken.selector);
        v2PoolLauncher.launch({_params: params, _recipient: users.charlie, _refundAddress: users.charlie});
    }

    modifier whenTheTokenToPairIsWhitelisted() {
        _;
    }

    function testFuzz_WhenTheBalanceOfPoolLauncherTokenOfTheSenderIsLowerThanAmountPoolLauncherToken(
        uint256 _amountPoolLauncherToken,
        uint256 _balancePoolLauncherToken,
        bool _stable,
        uint32 _lockDuration
    ) external whenThePoolHasNotBeenCreatedYet whenTheTokenToPairIsWhitelisted {
        // It should revert with {ERC20InsufficientBalance}
        _amountPoolLauncherToken = bound(_amountPoolLauncherToken, 1, MAX_TOKENS);
        _balancePoolLauncherToken = bound(_balancePoolLauncherToken, 0, _amountPoolLauncherToken - 1);
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: _lockDuration
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: _stable,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _balancePoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                users.alice,
                _balancePoolLauncherToken,
                _amountPoolLauncherToken
            )
        );

        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();
    }

    modifier whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken() {
        _;
    }

    function testFuzz_WhenTheBalanceOfTokenToPairOfTheSenderIsLowerThanAmountTokenToPair(
        uint256 _amountTokenToPair,
        uint256 _balanceTokenToPair,
        bool _stable,
        uint32 _lockDuration
    )
        external
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
    {
        // It should revert with {ERC20InsufficientBalance}
        _amountTokenToPair = bound(_amountTokenToPair, 1, MAX_TOKENS);
        _balanceTokenToPair = bound(_balanceTokenToPair, 0, _amountTokenToPair - 1);
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: _lockDuration
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: _stable,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _balanceTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
    }

    modifier whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair() {
        _;
    }

    function testFuzz_WhenLockDurationIsZero(bool _stable)
        external
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
    {
        // It should create a new pool launcher pool
        // It should return any seed liquidity to the recipient
        // It should refund any leftover tokens to the user
        // It should map the underlying pool to the pool parameters
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: _stable,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: _stable});
        vm.expectEmit({emitter: address(v2PoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: _poolLauncherToken,
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: _poolLauncherToken,
                tokenToPair: _tokenToPair
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        assertNotEq(pool.pool, address(0));
        assertEq(pool.pool, predictedUnderlyingPool);
        assertEq(pool.createdAt, block.timestamp);
        assertEq(lockerAddress, address(0));
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: _stable})
        );
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: _stable})
        );

        assertEq(IERC20(pool.pool).balanceOf(users.alice), 999999999999000);

        IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);
    }

    // function testFuzz_WhenLockDurationIsNotZeroOrUINT32_MAX(bool _stable, uint32 _lockDuration)
    //     external
    //     whenThePoolHasNotBeenCreatedYet
    //     whenTheTokenToPairIsWhitelisted
    //     whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
    //     whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
    // {
    //     // It should create a new pool launcher pool
    //     // It should lock the seed liquidity in a new Locker for the given duration
    //     // It should refund any leftover tokens to the user
    //     // It should map the underlying pool to the pool parameters
    //     // It should store the info for the new pool in storage
    //     // It should emit a {Launch} event
    //     uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
    //     uint256 _amountTokenToPair = 1000 * USDC_1;
    //     address _poolLauncherToken = address(token);
    //     address _tokenToPair = address(usdc);
    //     vm.assume(_lockDuration > 0 && _lockDuration < type(uint32).max);
    //     IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
    //         amountPoolLauncherToken: _amountPoolLauncherToken,
    //         amountTokenToPair: _amountTokenToPair,
    //         lockDuration: _lockDuration
    //     });
    //     IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
    //         poolLauncherToken: _poolLauncherToken,
    //         tokenToPair: _tokenToPair,
    //         stable: _stable,
    //         liquidity: liquidityParams
    //     });
    //     deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
    //     deal(_tokenToPair, users.alice, _amountTokenToPair);

    //     vm.startPrank(users.alice);
    //     token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
    //     usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
    //     address predictedUnderlyingPool =
    //         predictV2PoolAddress({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: _stable});
    //     address predictedLocker = address(
    //         uint160(
    //             uint256(
    //                 keccak256(
    //                     abi.encodePacked(
    //                         hex"d6", // list prefix
    //                         hex"94", // address length
    //                         v2LockerFactory,
    //                         uint8(1) // nonce = 1
    //                     )
    //                 )
    //             )
    //         )
    //     );
    //     vm.expectEmit({emitter: address(v2PoolLauncher)});
    //     emit IPoolLauncher.Launch({
    //         poolLauncherToken: _poolLauncherToken,
    //         pool: predictedUnderlyingPool,
    //         sender: users.alice,
    //         poolLauncherPool: IPoolLauncher.PoolLauncherPool({
    //             createdAt: uint32(block.timestamp),
    //             pool: predictedUnderlyingPool,
    //             locker: predictedLocker
    //         })
    //     });
    //     IPoolLauncher.PoolLauncherPool memory pool = v2PoolLauncher.launch({_params: params, _recipient: users.alice});

    //     assertNotEq(pool.pool, address(0));
    //     assertEq(pool.pool, predictedUnderlyingPool);
    //     assertEq(pool.createdAt, block.timestamp);
    //     assertEq(address(pool.locker), predictedLocker);
    //     assertEq(pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: _stable}));
    //     assertEq(pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: _stable}));

    //     uint256 lp = sqrt(_amountPoolLauncherToken * _amountTokenToPair) - MINIMUM_LIQUIDITY;
    //     assertEq(IERC20(pool.pool).balanceOf(address(pool.locker)), 999999999999000);
    //     assertEq(ILocker(lockerAddress).lp(), lp);
    //     assertEq(ILocker(pool.locker).lockedUntil(), block.timestamp + _lockDuration);
    //     assertEq(ILocker(pool.locker).pool(), pool.pool);
    //     assertEq(uint8(ILocker(pool.locker).poolType()), uint8(ILockerFactory.PoolType.BASIC));
    //     assertEq(ILocker(pool.locker).token0(), _poolLauncherToken);
    //     assertEq(ILocker(pool.locker).token1(), _tokenToPair);

    //     IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool =
    //         v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
    //     assertEq(newPoolLauncherPool.createdAt, block.timestamp);
    //     assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);
    //     assertEq(newPoolLauncherPool.locker, predictedLocker);
    // }

    function testFuzz_WhenLockDurationIsUINT32_MAX(bool _stable)
        external
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
    {
        // It should create a new pool launcher pool
        // It should permanently lock the seed liquidity in a new Locker
        // It should refund any leftover tokens to the user
        // It should map the underlying pool to the pool parameters
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: type(uint32).max
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: _stable,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: _stable});
        vm.expectEmit({emitter: address(v2PoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: _poolLauncherToken,
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: _poolLauncherToken,
                tokenToPair: _tokenToPair
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        assertNotEq(pool.pool, address(0));
        assertEq(pool.pool, predictedUnderlyingPool);
        assertEq(pool.createdAt, block.timestamp);
        {
            address predictedLocker = address(
                uint160(
                    uint256(
                        keccak256(
                            abi.encodePacked(
                                hex"d6", // list prefix
                                hex"94", // address length
                                v2LockerFactory,
                                uint8(1) // nonce = 1
                            )
                        )
                    )
                )
            );
            assertEq(lockerAddress, predictedLocker);
        }
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: _stable})
        );
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: _stable})
        );

        uint256 lp = sqrt(_amountPoolLauncherToken * _amountTokenToPair) - MINIMUM_LIQUIDITY;
        assertEq(IERC20(pool.pool).balanceOf(lockerAddress), 999999999999000);
        assertEq(ILocker(lockerAddress).lockedUntil(), type(uint32).max);
        assertEq(ILocker(lockerAddress).pool(), pool.pool);
        assertEq(ILocker(lockerAddress).lp(), lp);
        assertEq(uint8(ILocker(lockerAddress).poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(ILocker(lockerAddress).token0(), _poolLauncherToken);
        assertEq(ILocker(lockerAddress).token1(), _tokenToPair);

        IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);
    }
}
