// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLPoolLauncher.t.sol";

contract LaunchIntegrationConcreteTest is CLPoolLauncherTest {
    uint256 public poolLauncherAmount = TOKEN_1 * 1_000_000;
    uint256 public usdcAmount = USDC_1 * 1_000_000;
    int24 public tickLower;
    int24 public tickUpper;

    function setUp() public virtual override {
        super.setUp();

        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        vm.startPrank(users.alice);
        usdc.approve(address(clPoolLauncher), usdcAmount);
        token.approve(address(clPoolLauncher), poolLauncherAmount);
        vm.stopPrank();
    }

    function test_WhenThePoolLauncherTokenIsWhitelisted() external {
        // It should revert with {InvalidPoolLauncherToken}

        vm.prank(users.owner);
        clPoolLauncher.addPairableToken({_token: address(token)});

        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: encodePriceSqrt({reserve1: 1, reserve0: 1e12}),
            tickLower: getMinTick({tickSpacing: TICK_SPACING_200}),
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 0
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        vm.expectRevert(IPoolLauncher.InvalidPoolLauncherToken.selector);
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
    }

    modifier whenThePoolLauncherTokenIsNotWhitelisted() {
        _;
    }

    function test_WhenThePoolHasAlreadyBeenCreated() external whenThePoolLauncherTokenIsNotWhitelisted {
        // It should revert with {PoolAlreadyExists}
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: encodePriceSqrt({reserve1: 1, reserve0: 1e12}),
            tickLower: getMinTick({tickSpacing: TICK_SPACING_200}),
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 0
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});

        vm.prank(users.alice);
        vm.expectRevert(IPoolLauncher.PoolAlreadyExists.selector);
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
    }

    modifier whenThePoolHasNotBeenCreatedYet() {
        _;
    }

    function test_WhenTheTokenToPairIsNotNotWhitelisted()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
    {
        // It should revert with {InvalidToken}
        vm.prank(clPoolLauncher.owner());
        clPoolLauncher.removePairableToken({_token: address(usdc)});

        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: encodePriceSqrt({reserve1: 1, reserve0: 1e12}),
            tickLower: getMinTick({tickSpacing: TICK_SPACING_200}),
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 0
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        vm.expectRevert(IPoolLauncher.InvalidToken.selector);
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
    }

    modifier whenTheTokenToPairIsWhitelisted() {
        _;
    }

    function test_WhenTheTickForTheInitialPriceIsOutsideTheGivenRange()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenTheTokenToPairIsWhitelisted
        whenThePoolHasNotBeenCreatedYet
    {
        // It should revert with {InvalidSqrtPrice}
        int24 _tickLower = getMinTick({tickSpacing: TICK_SPACING_200});
        /// @dev Calculate `_sqrtPrice` for an out of bounds tick
        uint160 _sqrtPrice = TickMath.getSqrtRatioAtTick({tick: _tickLower - 1});

        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: _sqrtPrice,
            tickLower: _tickLower,
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 0
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        vm.expectRevert(ICLPoolLauncher.InvalidSqrtPrice.selector);
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
    }

    modifier whenTheTickForTheInitialPriceIsInsideTheGivenRange() {
        _;
    }

    function test_WhenTheAmountsDepositedAreSmallerThanTheMinAmounts()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheTickForTheInitialPriceIsInsideTheGivenRange
    {
        // It should revert with {PSC}
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            /// @dev Not accounting for leftovers in `amountMin` to simulate slippage
            amountPoolLauncherTokenMin: poolLauncherAmount,
            amountTokenToPairMin: usdcAmount,
            initialSqrtPriceX96: encodePriceSqrt({reserve1: 1, reserve0: 1e12}),
            tickLower: getMinTick({tickSpacing: TICK_SPACING_200}),
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 86400
        });
        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        vm.expectRevert(bytes("PSC"));
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
    }

    modifier whenTheTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts() {
        _;
    }

    function test_WhenLockDurationIsZero()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheTickForTheInitialPriceIsInsideTheGivenRange
        whenTheTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new pool launcher pool
        // It should mint a liquidity position to the user
        // It should refund any leftover tokens to the user
        // It should reset any oustanding allowances
        // It should map the underlying pool to the pool parameters
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint160 _sqrtPrice = encodePriceSqrt({reserve1: 1, reserve0: 1e12});
        int24 _tickLower = getMinTick({tickSpacing: TICK_SPACING_200});
        int24 _tickUpper = getMaxTick({tickSpacing: TICK_SPACING_200});
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: poolLauncherAmount - 1e6,
            amountTokenToPairMin: usdcAmount,
            initialSqrtPriceX96: _sqrtPrice,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            lockDuration: 0
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        uint256 lpCount = IERC721(nfpManager).balanceOf(users.alice);

        address predictedUnderlyingPool = predictCLPoolAddress({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            factory: clFactory
        });

        vm.prank(users.alice);
        vm.expectEmit({emitter: address(clPoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: address(token),
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});

        assertEq(pool.createdAt, block.timestamp);
        assertNotEq(pool.pool, address(0));
        assertEq(lockerAddress, address(0));
        assertEq(pool.pool, ICLFactory(clFactory).getPool(address(token), address(usdc), TICK_SPACING_200));
        assertEq(
            pool.pool,
            clPoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _tickSpacing: TICK_SPACING_200})
        );
        assertEq(
            pool.pool,
            clPoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _tickSpacing: TICK_SPACING_200})
        );

        assertEq(IERC721(nfpManager).balanceOf(users.alice), lpCount + 1);

        uint256 lp = IERC721(nfpManager).tokenOfOwnerByIndex(users.alice, lpCount);
        (,, address token0, address token1, int24 tickSpacingLP, int24 tickLowerLP, int24 tickUpperLP,,,,,) =
            INfpm(nfpManager).positions({tokenId: lp});
        assertEq(token0, address(token));
        assertEq(token1, address(usdc));
        assertEq(tickLowerLP, _tickLower);
        assertEq(tickUpperLP, _tickUpper);
        assertEq(tickSpacingLP, TICK_SPACING_200);

        /// @dev Ensure no outstanding balances or allowances in PoolLauncher
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(nfpManager)), 0);

        IPoolLauncher.PoolLauncherPool memory storedPool = clPoolLauncher.pools(pool.pool);
        assertEq(storedPool.createdAt, block.timestamp);
        assertEq(storedPool.pool, ICLFactory(clFactory).getPool(address(token), address(usdc), TICK_SPACING_200));

        /// @dev Ensure no outstanding balances in locker. Balance is used to launch or refunded back to user
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);
        assertEq(token.balanceOf(pool.pool), poolLauncherAmount - token.balanceOf(users.alice));
        assertEq(usdc.balanceOf(pool.pool), usdcAmount - usdc.balanceOf(users.alice));
        assertEq(token.balanceOf(users.alice), poolLauncherAmount - token.balanceOf(pool.pool));
        assertEq(usdc.balanceOf(users.alice), usdcAmount - usdc.balanceOf(pool.pool));
        assertGt(usdc.balanceOf(pool.pool), 0);
        assertGt(token.balanceOf(pool.pool), 0);
    }

    function test_WhenLockDurationIsNotZeroOrUINT32_MAX()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheTickForTheInitialPriceIsInsideTheGivenRange
        whenTheTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new pool launcher pool
        // It should mint a liquidity position
        // It should lock the liquidity position in a new Locker for the given duration
        // It should refund any leftover tokens to the user
        // It should reset any oustanding allowances
        // It should map the underlying pool to the pool parameters
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint160 _sqrtPrice = encodePriceSqrt({reserve1: 1, reserve0: 1e12});
        int24 _tickLower = getMinTick({tickSpacing: TICK_SPACING_200});
        int24 _tickUpper = getMaxTick({tickSpacing: TICK_SPACING_200});
        uint32 _lockDuration = 86400;
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: poolLauncherAmount - 1e6,
            amountTokenToPairMin: usdcAmount,
            initialSqrtPriceX96: _sqrtPrice,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            lockDuration: _lockDuration
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        address predictedUnderlyingPool = predictCLPoolAddress({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            factory: clFactory
        });

        vm.prank(users.alice);
        vm.expectEmit({emitter: address(clPoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: address(token),
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});

        assertEq(pool.createdAt, block.timestamp);
        assertNotEq(pool.pool, address(0));
        {
            address predictedLocker = predictLockerAddress({lockerFactory: address(clLockerFactory), nonce: 1});
            assertEq(lockerAddress, predictedLocker);
        }
        assertEq(pool.pool, ICLFactory(clFactory).getPool(address(token), address(usdc), TICK_SPACING_200));
        assertEq(
            pool.pool,
            clPoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _tickSpacing: TICK_SPACING_200})
        );
        assertEq(
            pool.pool,
            clPoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _tickSpacing: TICK_SPACING_200})
        );

        assertEq(IERC721(nfpManager).balanceOf(users.alice), 0);
        assertEq(IERC721(nfpManager).balanceOf(lockerAddress), 1);

        ICLLocker locker = ICLLocker(lockerAddress);
        assertEq(locker.pool(), pool.pool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.lockedUntil(), block.timestamp + _lockDuration);
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(locker.lp(), IERC721(nfpManager).tokenOfOwnerByIndex(lockerAddress, 0));
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertEq(locker.bribeableShare(), 500);
        assertEq(Ownable(lockerAddress).owner(), users.alice);

        (,, address token0, address token1, int24 tickSpacingLP, int24 tickLowerLP, int24 tickUpperLP,,,,,) =
            INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(token0, address(token));
        assertEq(token1, address(usdc));
        assertEq(tickLowerLP, _tickLower);
        assertEq(tickUpperLP, _tickUpper);
        assertEq(tickSpacingLP, TICK_SPACING_200);

        /// @dev Ensure no outstanding balances or allowances in PoolLauncher
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(nfpManager)), 0);

        IPoolLauncher.PoolLauncherPool memory storedPool = clPoolLauncher.pools(pool.pool);
        assertEq(storedPool.createdAt, block.timestamp);
        assertEq(storedPool.pool, ICLFactory(clFactory).getPool(address(token), address(usdc), TICK_SPACING_200));

        /// @dev Ensure no outstanding balances in locker. Balance is used to launch or refunded back to user
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);
        assertEq(token.balanceOf(pool.pool), poolLauncherAmount - token.balanceOf(users.alice));
        assertEq(usdc.balanceOf(pool.pool), usdcAmount - usdc.balanceOf(users.alice));
        assertEq(token.balanceOf(users.alice), poolLauncherAmount - token.balanceOf(pool.pool));
        assertEq(usdc.balanceOf(users.alice), usdcAmount - usdc.balanceOf(pool.pool));
        assertGt(usdc.balanceOf(pool.pool), 0);
        assertGt(token.balanceOf(pool.pool), 0);
    }

    function test_WhenLockDurationIsUINT32_MAX()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheTickForTheInitialPriceIsInsideTheGivenRange
        whenTheTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new pool launcher pool
        // It should mint a liquidity position
        // It should permanently lock the liquidity position in a new Locker
        // It should refund any leftover tokens to the user
        // It should reset any oustanding allowances
        // It should map the underlying pool to the pool parameters
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event

        poolLauncherAmount = TOKEN_1 * 10_000_000;
        usdcAmount = USDC_1 * 100_000;
        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        /// @dev Create unbalanced pool to simulate leftovers
        vm.startPrank(users.alice);
        ICLFactory(clFactory).createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            /// @dev Use slightly different price to simulate slippage
            sqrtPriceX96: encodePriceSqrt({reserve1: 1, reserve0: 2e12})
        });

        uint160 _sqrtPrice = encodePriceSqrt({reserve1: 1, reserve0: 1e12});
        tickLower = getMinTick({tickSpacing: TICK_SPACING_200});
        tickUpper = getMaxTick({tickSpacing: TICK_SPACING_200});

        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            /// @dev Smaller `amountPoolLauncherTokenMin` to account for slippage
            amountPoolLauncherTokenMin: TOKEN_1 * 200_000,
            amountTokenToPairMin: usdcAmount,
            initialSqrtPriceX96: _sqrtPrice,
            tickLower: tickLower,
            tickUpper: tickUpper,
            lockDuration: type(uint32).max
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        address predictedUnderlyingPool = predictCLPoolAddress({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            factory: clFactory
        });
        address predictedLocker = predictLockerAddress({lockerFactory: address(clLockerFactory), nonce: 1});
        uint256 oldPoolBal = token.balanceOf(predictedUnderlyingPool);

        usdc.approve(address(clPoolLauncher), usdcAmount);
        token.approve(address(clPoolLauncher), poolLauncherAmount);
        vm.expectEmit({emitter: address(clPoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: address(token),
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});

        assertEq(pool.createdAt, block.timestamp);
        assertNotEq(pool.pool, address(0));
        assertEq(lockerAddress, predictedLocker);
        assertEq(pool.pool, ICLFactory(clFactory).getPool(address(token), address(usdc), TICK_SPACING_200));
        assertEq(
            pool.pool,
            clPoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _tickSpacing: TICK_SPACING_200})
        );
        assertEq(
            pool.pool,
            clPoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _tickSpacing: TICK_SPACING_200})
        );

        assertEq(IERC721(nfpManager).balanceOf(users.alice), 0);
        assertEq(IERC721(nfpManager).balanceOf(lockerAddress), 1);

        ICLLocker locker = ICLLocker(lockerAddress);
        assertEq(locker.pool(), pool.pool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(locker.lockedUntil(), type(uint32).max);
        assertEq(locker.lp(), IERC721(nfpManager).tokenOfOwnerByIndex(lockerAddress, 0));
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertEq(locker.bribeableShare(), 500);
        assertEq(Ownable(lockerAddress).owner(), users.alice);

        (,, address token0, address token1, int24 tickSpacingLP, int24 tickLowerLP, int24 tickUpperLP,,,,,) =
            INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(token0, address(token));
        assertEq(token1, address(usdc));
        assertEq(tickLowerLP, tickLower);
        assertEq(tickUpperLP, tickUpper);
        assertEq(tickSpacingLP, TICK_SPACING_200);

        /// @dev Ensure no outstanding balances or allowances in PoolLauncher
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(nfpManager)), 0);

        /// @dev Ensure leftover is sent to alice
        uint256 depositedBal = token.balanceOf(predictedUnderlyingPool) - oldPoolBal;
        assertEq(token.balanceOf(users.alice), poolLauncherAmount - depositedBal);
        assertEq(usdc.balanceOf(users.alice), 0);
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(usdc.balanceOf(address(locker)), 0);

        IPoolLauncher.PoolLauncherPool memory storedPool = clPoolLauncher.pools(pool.pool);
        assertEq(storedPool.createdAt, block.timestamp);
        assertEq(storedPool.pool, ICLFactory(clFactory).getPool(address(token), address(usdc), TICK_SPACING_200));

        /// @dev Ensure no outstanding balances in locker. Balance is used to launch or refunded back to user
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);
        assertEq(token.balanceOf(pool.pool), poolLauncherAmount - token.balanceOf(users.alice));
        assertEq(usdc.balanceOf(pool.pool), usdcAmount - usdc.balanceOf(users.alice));
        assertEq(token.balanceOf(users.alice), poolLauncherAmount - token.balanceOf(pool.pool));
        assertEq(usdc.balanceOf(users.alice), usdcAmount - usdc.balanceOf(pool.pool));
        assertGt(usdc.balanceOf(pool.pool), 0);
        assertGt(token.balanceOf(pool.pool), 0);
    }

    function testGas_launch()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheTickForTheInitialPriceIsInsideTheGivenRange
        whenTheTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: poolLauncherAmount - 1e6,
            amountTokenToPairMin: usdcAmount,
            initialSqrtPriceX96: encodePriceSqrt({reserve1: 1, reserve0: 1e12}),
            tickLower: getMinTick({tickSpacing: TICK_SPACING_200}),
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 86400
        });
        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
        vm.snapshotGasLastCall("CLPoolLauncher_launch");
    }
}
