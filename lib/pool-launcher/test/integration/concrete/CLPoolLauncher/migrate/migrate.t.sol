// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLPoolLauncher.t.sol";

contract MigrateIntegrationConcreteTest is CLPoolLauncherTest {
    using stdStorage for StdStorage;

    uint256 public constant poolLauncherAmount = TOKEN_1 * 1_000_000;
    uint256 public constant usdcAmount = USDC_1 * 1_000_000;
    uint32 public constant lockDuration = 86400;
    uint256 public depositedPoolLauncherAmount;
    uint256 public depositedUsdcAmount;

    // CL PoolLauncher contracts
    CLLockerFactory public newCLLockerFactory;
    CLPoolLauncher public newCLPoolLauncher;
    address public newNfpManager;
    address public newCLFactory;
    ICLLocker public locker;

    uint256 public oldLP;
    address public oldPool;
    address public oldLocker;
    uint128 public lockedLiquidity;
    int24 public immutable tickLower = getMinTick({tickSpacing: TICK_SPACING_200});
    int24 public immutable tickUpper = getMaxTick({tickSpacing: TICK_SPACING_200});

    function parsedAddresses() internal view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/test/e2e/addresses-op.json"));
        return vm.readFile(path);
    }

    function setUp() public virtual override {
        vm.createSelectFork({urlOrAlias: "optimism", blockNumber: 140500000});
        BaseFixture.setUp();

        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        vm.startPrank(users.alice);
        usdc.approve(address(clPoolLauncher), usdcAmount);
        token.approve(address(clPoolLauncher), poolLauncherAmount);
        vm.stopPrank();

        /// @dev USDC is token0, `poolLauncherToken` is token1
        uint160 sqrtPrice = encodePriceSqrt({reserve1: 1e12, reserve0: 1});
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: sqrtPrice,
            tickLower: tickLower,
            tickUpper: tickUpper,
            lockDuration: lockDuration
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        IPoolLauncher.PoolLauncherPool memory poolLauncherPool;
        (poolLauncherPool, oldLocker) = clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
        oldPool = poolLauncherPool.pool;
        oldLP = ILocker(oldLocker).lp();

        // Calculate deposited liquidity amounts
        depositedPoolLauncherAmount = poolLauncherAmount - token.balanceOf(users.alice);
        depositedUsdcAmount = usdcAmount - usdc.balanceOf(users.alice);

        (,,,,,,, lockedLiquidity,,,,) = INfpm(nfpManager).positions({tokenId: oldLP});

        // Deploy new PoolLauncher contracts to migrate into
        /// @dev Using old CL deployment in new CL PoolLauncher for testing
        newNfpManager = OLD_NFPM_OP;
        newCLFactory = address(INfpm(newNfpManager).factory());
        deployCLParams = DeployCLFixture.DeploymentParameters({
            owner: users.owner,
            voter: voter,
            nfpManager: newNfpManager,
            outputFilename: "test.json"
        });
        deployCL = new TestDeployCL({_params_: deployCLParams});
        stdstore.target(address(deployCL)).sig("deployer()").checked_write(users.deployer2);
        deployCL.run();
        newCLLockerFactory = deployCL.clLockerFactory();
        newCLPoolLauncher = deployCL.clPoolLauncher();

        assertNotEq(address(newCLPoolLauncher.nfpManager()), address(clPoolLauncher.nfpManager()));
        assertNotEq(address(newCLPoolLauncher.clFactory()), address(clPoolLauncher.clFactory()));

        vm.prank(users.owner);
        newCLPoolLauncher.addPairableToken({_token: address(usdc)});
    }

    /// @dev Helper function used to create pool with `poolLauncherToken` as `token0`
    function _setToken0() internal {
        /// @dev Simulate token with smaller address
        address newToken = address(uint160(address(usdc)) - 1);
        vm.etch({target: address(newToken), newRuntimeBytecode: address(token).code});
        token = IERC20(newToken);
        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        vm.startPrank(users.alice);
        usdc.approve(address(clPoolLauncher), usdcAmount);
        token.approve(address(clPoolLauncher), poolLauncherAmount);
        vm.stopPrank();

        uint160 sqrtPrice = encodePriceSqrt({reserve1: 1, reserve0: 1e12});
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: sqrtPrice,
            tickLower: tickLower,
            tickUpper: tickUpper,
            lockDuration: lockDuration
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        IPoolLauncher.PoolLauncherPool memory poolLauncherPool;
        (poolLauncherPool, oldLocker) = clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
        oldPool = poolLauncherPool.pool;
        oldLP = ILocker(oldLocker).lp();

        // Calculate deposited liquidity amounts
        depositedPoolLauncherAmount = poolLauncherAmount - token.balanceOf(users.alice);
        depositedUsdcAmount = usdcAmount - usdc.balanceOf(users.alice);

        (,,,,,,, lockedLiquidity,,,,) = INfpm(nfpManager).positions({tokenId: oldLP});
    }

    function test_WhenTheNewPoolLauncherIsNotSet() external {
        // It should revert with {NewPoolLauncherNotSet}
        vm.prank(users.alice);
        vm.expectRevert(IPoolLauncher.NewPoolLauncherNotSet.selector);
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheNewPoolLauncherIsSet() {
        vm.startPrank(clLockerFactory.owner());
        clPoolLauncher.setNewPoolLauncher({_newPoolLauncher: address(newCLPoolLauncher)});
        clLockerFactory.setNewLockerFactory({_lockerFactory: address(newCLLockerFactory)});
        vm.stopPrank();
        _;
    }

    function test_WhenTheCallerIsNotTheLockerOwner() external whenTheNewPoolLauncherIsSet {
        // It should revert with {NotLockerOwner}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(IPoolLauncher.NotLockerOwner.selector);
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheCallerIsTheLockerOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerHasExpired() external whenTheNewPoolLauncherIsSet whenTheCallerIsTheLockerOwner {
        // It should revert with {NotLocked}
        skip(lockDuration);
        vm.expectRevert(IPoolLauncher.NotLocked.selector);
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheLockerHasNotExpired() {
        _;
    }

    function test_WhenTheUnderlyingPoolIsNotRegisteredInPoolLauncher()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
    {
        // It should revert with {PoolNotInPoolLauncher}

        /// @dev Create new token with no pool registered in launcher
        token = IERC20(new BasicERC20("Token", "TKN", 100 ether));
        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);
        vm.startPrank(users.alice);
        uint160 sqrtPrice = encodePriceSqrt({reserve1: 1e12, reserve0: 1});
        oldPool = ICLFactory(clFactory).createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            sqrtPriceX96: sqrtPrice
        });
        usdc.approve(address(clLockerFactory), usdcAmount);
        token.approve(address(clLockerFactory), poolLauncherAmount);

        oldLP = mintLP({
            token0: address(token) < address(usdc) ? address(token) : address(usdc),
            token1: address(token) < address(usdc) ? address(usdc) : address(token),
            tickSpacing: TICK_SPACING_200,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0: address(token) < address(usdc) ? poolLauncherAmount : usdcAmount,
            amount1: address(token) < address(usdc) ? usdcAmount : poolLauncherAmount,
            recipient: users.alice
        });
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: oldLP});
        oldLocker = clLockerFactory.lock({
            _lp: oldLP,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 500,
            _owner: users.alice
        });
        vm.stopPrank();

        vm.startPrank(users.alice);
        vm.expectRevert(IPoolLauncher.PoolNotInPoolLauncher.selector);
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheUnderlyingPoolIsRegisteredInPoolLauncher() {
        _;
    }

    function test_WhenTheAmountsToUnlockAreSmallerThanTheAmountsToMigrate()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
    {
        // It should revert with {InsufficientPoolLauncherUnlockMin}

        vm.expectRevert(IPoolLauncher.InsufficientPoolLauncherUnlockMin.selector);
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 1,
            _tokenToPairAmountMin: 0
        });

        vm.expectRevert(IPoolLauncher.InsufficientTokenToPairUnlockMin.selector);
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 1
        });
    }

    modifier whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate() {
        _;
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should revert with {PS}

        /// @dev Not accounting for slippage to simulate revert
        vm.expectRevert(bytes("PS"));
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: depositedPoolLauncherAmount,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });

        /// @dev Not accounting for slippage to simulate revert
        vm.expectRevert(bytes("PS"));
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: depositedUsdcAmount,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock() {
        _;
    }

    function test_WhenTheAmountsMigratedAreSmallerThanTheMinAmounts()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
    {
        // It should revert with {PSC}

        /// @dev Create unbalanced pool on new pool factory
        usdc.approve(newCLFactory, usdcAmount);
        token.approve(newCLFactory, poolLauncherAmount);
        ICLFactory(newCLFactory).createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            /// @dev Use slightly different price to simulate slippage
            sqrtPriceX96: encodePriceSqrt({reserve1: 2e12, reserve0: 1})
        });

        /// @dev Reset Alice's balances
        deal(address(usdc), users.alice, 0);
        deal(address(token), users.alice, 0);

        /// @dev Not accounting for slippage to simulate revert
        vm.expectRevert(bytes("PSC"));
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: depositedPoolLauncherAmount - 1,
            _tokenToPairUnlockMin: depositedUsdcAmount - 1,
            _poolLauncherAmountMin: poolLauncherAmount - 1e12,
            _tokenToPairAmountMin: usdcAmount - 1
        });
    }

    modifier whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts() {
        _;
    }

    function test_WhenThePoolLauncherTokenIsToken0()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should migrate the pool launcher pool to the new pool launcher
        // It should migrate the locker to the new locker factory
        // It should refund leftover to new locker
        // It should emit a {Migrate} event
        _setToken0();
        assertEq(ICLPool(oldPool).token0(), address(token));

        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        deal(address(usdc), oldLocker, USDC_1);
        deal(address(token), oldLocker, TOKEN_1);

        uint256 balanceToken0AliceBefore = token.balanceOf(users.alice);
        address predictedLocker = predictLockerAddress({lockerFactory: address(newCLLockerFactory), nonce: 1});
        address predictedPool = predictCLPoolAddress({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            factory: address(newCLFactory)
        });
        (,,,,,,, uint128 oldLiquidity,,,,) = INfpm(nfpManager).positions({tokenId: ILocker(oldLocker).lp()});
        (uint160 oldSqrtPrice,,,,,) = ICLPool(oldPool).slot0();

        vm.startPrank(users.alice);
        vm.expectCall(oldLocker, abi.encodeCall(ILocker.unlock, (address(clLockerFactory), address(clPoolLauncher))));
        vm.expectCall(
            address(clLockerFactory),
            abi.encodeCall(
                ILockerFactory.migrate,
                (
                    oldLocker,
                    depositedPoolLauncherAmount - 1,
                    depositedUsdcAmount - 1,
                    poolLauncherAmount - 1e12,
                    usdcAmount - 1
                )
            )
        );
        vm.expectEmit({emitter: address(clPoolLauncher)});
        emit IPoolLauncher.Migrate({
            underlyingPool: oldPool,
            locker: oldLocker,
            newPoolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedPool,
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            }),
            newLocker: predictedLocker
        });
        (IPoolLauncher.PoolLauncherPool memory newPool, address newLocker) = clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: depositedPoolLauncherAmount - 1,
            _tokenToPairUnlockMin: depositedUsdcAmount - 1,
            _poolLauncherAmountMin: poolLauncherAmount - 1e12,
            _tokenToPairAmountMin: usdcAmount - 1
        });
        assertEq(newPool.createdAt, block.timestamp);
        assertEq(newPool.pool, predictedPool);
        assertEq(newPool.poolLauncherToken, address(token));
        assertEq(newPool.tokenToPair, address(usdc));
        assertEq(newLocker, predictedLocker);

        newPool = newCLPoolLauncher.pools({_underlyingPool: predictedPool});
        assertEq(newPool.createdAt, block.timestamp);
        assertEq(newPool.pool, predictedPool);
        assertEq(newPool.poolLauncherToken, address(token));
        assertEq(newPool.tokenToPair, address(usdc));
        assertTrue(newCLLockerFactory.instances(newLocker));

        /// @dev Assert new locker state
        locker = ICLLocker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(address(locker.nfpManager()), newNfpManager);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(newCLLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(locker.pool(), newPool.pool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertTrue(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(locker.staked());

        assertEq(INfpm(newNfpManager).ownerOf(locker.lp()), address(locker));

        /// @dev Assert new LP
        (
            ,
            ,
            address token0,
            address token1,
            int24 tickSpacingLP,
            int24 tickLowerLP,
            int24 tickUpperLP,
            uint128 newLiquidity,
            ,
            ,
            ,
        ) = INfpm(newCLLockerFactory.nfpManager()).positions({tokenId: ILocker(newLocker).lp()});
        assertEq(token0, address(token));
        assertEq(token1, address(usdc));
        assertEq(tickSpacingLP, TICK_SPACING_200);
        assertEq(tickLowerLP, tickLower);
        assertEq(tickUpperLP, tickUpper);
        assertApproxEqAbs(newLiquidity, oldLiquidity, 1e6);
        (uint160 sqrtPrice,,,,,) = ICLPool(newPool.pool).slot0();
        assertEq(sqrtPrice, oldSqrtPrice);

        /// @dev Ensure no outstanding balances or allowances in pool launcher contracts
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);

        assertEq(usdc.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(token.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(usdc.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);

        /// @dev Refunds leftover from slippage and old locker balance to new locker
        assertGt(token.balanceOf(predictedPool), 0);
        assertGt(usdc.balanceOf(predictedPool), 0);
        assertApproxEqAbs(
            token.balanceOf(newLocker), depositedPoolLauncherAmount + TOKEN_1 - token.balanceOf(predictedPool), 1
        );
        assertApproxEqAbs(usdc.balanceOf(newLocker), depositedUsdcAmount + USDC_1 - usdc.balanceOf(predictedPool), 1);
        assertEq(token.balanceOf(users.alice), balanceToken0AliceBefore);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function test_WhenThePoolLauncherTokenIsToken1()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should sort the tokens
        // It should migrate the pool launcher pool to the new pool launcher
        // It should migrate the locker to the new locker factory
        // It should refund leftover to new locker
        // It should emit a {Migrate} event
        assertEq(ICLPool(oldPool).token1(), address(token));

        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        deal(address(usdc), oldLocker, USDC_1);
        deal(address(token), oldLocker, TOKEN_1);

        address predictedLocker = predictLockerAddress({lockerFactory: address(newCLLockerFactory), nonce: 1});
        address predictedPool = predictCLPoolAddress({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            factory: address(newCLFactory)
        });
        (,,,,,,, uint128 oldLiquidity,,,,) = INfpm(nfpManager).positions({tokenId: ILocker(oldLocker).lp()});
        (uint160 oldSqrtPrice,,,,,) = ICLPool(oldPool).slot0();

        vm.expectCall(oldLocker, abi.encodeCall(ILocker.unlock, (address(clLockerFactory), address(clPoolLauncher))));
        vm.expectCall(
            address(clLockerFactory),
            abi.encodeCall(
                ILockerFactory.migrate,
                (
                    oldLocker,
                    depositedUsdcAmount - 1,
                    depositedPoolLauncherAmount - 1,
                    usdcAmount - 1,
                    poolLauncherAmount - 1e12
                )
            )
        );
        vm.expectEmit({emitter: address(clPoolLauncher)});
        emit IPoolLauncher.Migrate({
            underlyingPool: oldPool,
            locker: oldLocker,
            newPoolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedPool,
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            }),
            newLocker: predictedLocker
        });
        (IPoolLauncher.PoolLauncherPool memory newPool, address newLocker) = clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: depositedPoolLauncherAmount - 1,
            _tokenToPairUnlockMin: depositedUsdcAmount - 1,
            _poolLauncherAmountMin: poolLauncherAmount - 1e12,
            _tokenToPairAmountMin: usdcAmount - 1
        });
        assertEq(newPool.createdAt, block.timestamp);
        assertEq(newPool.pool, predictedPool);
        assertEq(newPool.poolLauncherToken, address(token));
        assertEq(newPool.tokenToPair, address(usdc));
        assertEq(newLocker, predictedLocker);

        newPool = newCLPoolLauncher.pools({_underlyingPool: predictedPool});
        assertEq(newPool.createdAt, block.timestamp);
        assertEq(newPool.pool, predictedPool);
        assertEq(newPool.poolLauncherToken, address(token));
        assertEq(newPool.tokenToPair, address(usdc));
        assertTrue(newCLLockerFactory.instances(newLocker));

        /// @dev Assert new locker state
        locker = ICLLocker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(address(locker.nfpManager()), newNfpManager);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(newCLLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(locker.pool(), newPool.pool);
        assertEq(locker.token0(), address(usdc));
        assertEq(locker.token1(), address(token));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertTrue(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(locker.staked());

        assertEq(INfpm(newNfpManager).ownerOf(locker.lp()), address(locker));

        (
            ,
            ,
            address token0,
            address token1,
            int24 tickSpacingLP,
            int24 tickLowerLP,
            int24 tickUpperLP,
            uint128 newLiquidity,
            ,
            ,
            ,
        ) = INfpm(newCLLockerFactory.nfpManager()).positions({tokenId: ILocker(newLocker).lp()});
        assertEq(token0, address(usdc));
        assertEq(token1, address(token));
        assertEq(tickSpacingLP, TICK_SPACING_200);
        assertEq(tickLowerLP, tickLower);
        assertEq(tickUpperLP, tickUpper);
        assertApproxEqAbs(newLiquidity, oldLiquidity, 1e6);
        (uint160 sqrtPrice,,,,,) = ICLPool(newPool.pool).slot0();
        assertEq(sqrtPrice, oldSqrtPrice);

        /// @dev Ensure no outstanding balances or allowances in pool launcher contracts
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);

        assertEq(usdc.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(token.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(usdc.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);

        /// @dev Refunds leftover from slippage and old locker balance to new locker
        assertGt(token.balanceOf(predictedPool), 0);
        assertGt(usdc.balanceOf(predictedPool), 0);
        assertApproxEqAbs(
            token.balanceOf(newLocker), depositedPoolLauncherAmount + TOKEN_1 - token.balanceOf(predictedPool), 1
        );
        assertApproxEqAbs(usdc.balanceOf(newLocker), depositedUsdcAmount + USDC_1 - usdc.balanceOf(predictedPool), 1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function test_WhenThePoolLauncherTokenIsToken1_RefundFlow()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should sort the tokens
        // It should migrate the pool launcher pool to the new pool launcher
        // It should migrate the locker to the new locker factory
        // It should refund leftover to new locker
        // It should emit a {Migrate} event
        assertEq(ICLPool(oldPool).token1(), address(token));

        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        deal(address(usdc), oldLocker, USDC_1);
        deal(address(token), oldLocker, TOKEN_1);

        /// @dev Create unbalanced pool on new pool factory
        usdc.approve(newCLFactory, usdcAmount);
        token.approve(newCLFactory, poolLauncherAmount);
        address poolAddr = ICLFactory(newCLFactory).createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            /// @dev Use slightly different price to simulate slippage
            sqrtPriceX96: encodePriceSqrt({reserve1: 2e12, reserve0: 1})
        });

        /// @dev Reset Alice's balances
        deal(address(usdc), users.alice, 0);
        deal(address(token), users.alice, 0);

        address predictedLocker = predictLockerAddress({lockerFactory: address(newCLLockerFactory), nonce: 1});

        vm.expectCall(oldLocker, abi.encodeCall(ILocker.unlock, (address(clLockerFactory), address(clPoolLauncher))));
        vm.expectCall(
            address(clLockerFactory),
            abi.encodeCall(
                ILockerFactory.migrate,
                (
                    oldLocker,
                    depositedUsdcAmount - 1,
                    depositedPoolLauncherAmount - 1,
                    usdcAmount / 2,
                    poolLauncherAmount - 1e6
                )
            )
        );
        vm.expectEmit(true, true, false, false, address(token));
        emit IERC20.Transfer({from: address(clPoolLauncher), to: predictedLocker, value: 0});
        vm.expectEmit({emitter: address(clPoolLauncher)});
        emit IPoolLauncher.Migrate({
            underlyingPool: oldPool,
            locker: oldLocker,
            newPoolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: poolAddr,
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            }),
            newLocker: predictedLocker
        });
        (IPoolLauncher.PoolLauncherPool memory newPool, address newLocker) = clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: depositedPoolLauncherAmount - 1,
            _tokenToPairUnlockMin: depositedUsdcAmount - 1,
            _poolLauncherAmountMin: poolLauncherAmount - 1e6,
            _tokenToPairAmountMin: usdcAmount / 2
        });
        assertEq(newPool.createdAt, block.timestamp);
        assertEq(newPool.pool, poolAddr);
        assertEq(newPool.poolLauncherToken, address(token));
        assertEq(newPool.tokenToPair, address(usdc));
        assertEq(newLocker, predictedLocker);

        newPool = newCLPoolLauncher.pools({_underlyingPool: poolAddr});
        assertEq(newPool.createdAt, block.timestamp);
        assertEq(newPool.pool, poolAddr);
        assertEq(newPool.poolLauncherToken, address(token));
        assertEq(newPool.tokenToPair, address(usdc));
        assertTrue(newCLLockerFactory.instances(newLocker));

        /// @dev Assert new locker state
        locker = ICLLocker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(address(locker.nfpManager()), newNfpManager);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(newCLLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(locker.pool(), newPool.pool);
        assertEq(locker.token0(), address(usdc));
        assertEq(locker.token1(), address(token));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertTrue(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(locker.staked());

        assertEq(INfpm(newNfpManager).ownerOf(locker.lp()), address(locker));

        (
            ,
            ,
            address token0,
            address token1,
            int24 tickSpacingLP,
            int24 tickLowerLP,
            int24 tickUpperLP,
            uint128 newLiquidity,
            ,
            ,
            ,
        ) = INfpm(newCLLockerFactory.nfpManager()).positions({tokenId: ILocker(newLocker).lp()});
        assertEq(token0, address(usdc));
        assertEq(token1, address(token));
        assertEq(tickSpacingLP, TICK_SPACING_200);
        assertEq(tickLowerLP, tickLower);
        assertEq(tickUpperLP, tickUpper);

        {
            /// @dev New pool has different price and slightly less liquidity due to slippage
            assertEq(newLiquidity, 707106781186547524);
            (uint160 sqrtPrice,,,,,) = ICLPool(newPool.pool).slot0();
            assertEq(sqrtPrice, encodePriceSqrt({reserve1: 2e12, reserve0: 1}));
        }

        /// @dev Ensure no outstanding balances or allowances in pool launcher contracts
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);

        assertEq(usdc.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(token.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(usdc.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);

        /// @dev Refunds leftover from slippage and old locker balance to new locker
        assertGt(token.balanceOf(poolAddr), 0);
        assertGt(usdc.balanceOf(poolAddr), 0);
        assertApproxEqAbs(
            token.balanceOf(newLocker), depositedPoolLauncherAmount + TOKEN_1 - token.balanceOf(poolAddr), 1
        );
        assertApproxEqAbs(usdc.balanceOf(newLocker), depositedUsdcAmount + USDC_1 - usdc.balanceOf(poolAddr), 1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function testGas_WhenThePoolLauncherTokenIsToken1()
        external
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: depositedPoolLauncherAmount - 1,
            _tokenToPairUnlockMin: depositedUsdcAmount - 1,
            _poolLauncherAmountMin: poolLauncherAmount - 1e12,
            _tokenToPairAmountMin: usdcAmount - 1
        });
        vm.snapshotGasLastCall("CLPoolLauncher_migrate");
    }
}
