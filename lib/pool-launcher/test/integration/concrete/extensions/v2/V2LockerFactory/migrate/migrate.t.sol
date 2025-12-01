// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2LockerFactory.t.sol";

contract MigrateUnitConcreteTest is V2LockerFactoryTest {
    using stdStorage for StdStorage;

    V2PoolLauncher public oldV2PoolLauncher;
    V2LockerFactory public oldV2LockerFactory;
    address public poolToMigrate;
    address public lockerToMigrate;

    uint256 public amountPoolLauncherToken = 1000 * TOKEN_1;
    uint256 public amountTokenToPair = 1000 * USDC_1;
    uint16 public constant beneficiaryShare = 500;
    uint16 public constant bribeableShare = 1000;

    address public oldV2Factory;
    address public oldV2Router;

    function setUp() public virtual override {
        /// @dev Avoid locking liquidity in setUp
        lockLiquidity = false;

        super.setUp();

        oldV2PoolLauncher = v2PoolLauncher;
        oldV2LockerFactory = v2LockerFactory;
        oldV2Factory = v2Factory;
        oldV2Router = v2Router;

        poolToMigrate = v2Pool;
        lockerToMigrate = address(locker);

        // deploy new pool launcher and locker factory
        v2Factory = address(new MockV2Factory());
        v2Router = makeAddr("router");
        deployV2Params = DeployV2Fixture.DeploymentParameters({
            v2Factory: v2Factory,
            v2Router: v2Router,
            voter: voter,
            owner: users.owner,
            outputFilename: "test.json"
        });
        deployV2 = new TestDeployV2({_params_: deployV2Params});
        stdstore.target(address(deployV2)).sig("deployer()").checked_write(users.deployer2);
        deployV2.run();

        vm.etch({target: address(v2Factory), newRuntimeBytecode: address(oldV2PoolLauncher.v2Factory()).code});
        /// @dev Redeploy flattened router to overwrite immutable variables
        address factoryRegistry = makeAddr("factoryRegistry");
        vm.etch({
            target: address(v2Router),
            newRuntimeBytecode: address(
                new Router({
                    _forwarder: address(0),
                    _factoryRegistry: factoryRegistry,
                    _factory: v2Factory,
                    _voter: address(0),
                    _weth: address(0)
                })
            ).code
        });
        vm.mockCall(
            factoryRegistry, abi.encodeWithSelector(IFactoryRegistry.isPoolFactoryApproved.selector), abi.encode(true)
        );
        v2PoolLauncher = deployV2.v2PoolLauncher();
        v2LockerFactory = deployV2.v2LockerFactory();

        vm.prank(users.owner);
        v2PoolLauncher.addPairableToken({_token: address(usdc)});

        /// @dev Manually lock LP tokens with custom params
        vm.startPrank(users.alice);
        IERC20(v2Pool).approve({spender: address(oldV2LockerFactory), value: lp});
        lockerToMigrate = oldV2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare,
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
        locker = IV2Locker(lockerToMigrate);
        vm.stopPrank();
    }

    function test_InitialState() public override {
        assertEq(v2LockerFactory.v2Factory(), v2Factory);
        assertEq(v2LockerFactory.v2Router(), v2Router);

        assertEq(Ownable(v2LockerFactory).owner(), users.owner);
        assertEq(v2LockerFactory.MAX_BPS(), MAX_BPS);
        assertEq(v2LockerFactory.voter(), voter);
        assertEq(uint8(v2LockerFactory.poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(v2LockerFactory.newLockerFactory(), address(0));
        assertEq(v2LockerFactory.poolLauncher(), address(v2PoolLauncher));

        _assertMappings(0, address(0), address(0));

        assertEq(oldV2LockerFactory.v2Factory(), oldV2Factory);
        assertEq(oldV2LockerFactory.v2Router(), oldV2Router);

        assertEq(Ownable(oldV2LockerFactory).owner(), users.owner);
        assertEq(oldV2LockerFactory.MAX_BPS(), MAX_BPS);
        assertEq(oldV2LockerFactory.voter(), voter);
        assertEq(uint8(oldV2LockerFactory.poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(oldV2LockerFactory.newLockerFactory(), address(0));
        assertEq(oldV2LockerFactory.poolLauncher(), address(oldV2PoolLauncher));

        v2LockerFactory = oldV2LockerFactory;
        _assertMappings(1, address(0), address(0));
    }

    function test_WhenTheNewLockerFactoryIsNotSet() external {
        // It should revert with {MigrationDisabled}
        vm.startPrank(users.charlie);
        vm.expectRevert(ILockerFactory.MigrationDisabled.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: 0,
            _unlock1Min: 0,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    modifier whenTheNewLockerFactoryIsSet() {
        vm.prank(users.owner);
        oldV2LockerFactory.setNewLockerFactory({_lockerFactory: address(v2LockerFactory)});
        _;
    }

    function test_WhenTheLockerIsNotAValidInstance() external whenTheNewLockerFactoryIsSet {
        // It should revert with {NotLocker}
        vm.startPrank(users.charlie);
        vm.expectRevert(ILockerFactory.NotLocker.selector);
        oldV2LockerFactory.migrate({_locker: address(0), _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheLockerIsAValidInstance() {
        _;
    }

    function test_WhenTheCallerIsNotTheLockerOwner()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
    {
        // It should revert with {NotLockerOwner}
        vm.startPrank(users.charlie);
        vm.expectRevert(ILockerFactory.NotLockerOwner.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: 0,
            _unlock1Min: 0,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    modifier whenTheCallerIsTheLockerOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerHasExpired()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
    {
        // It should revert with {NotLocked}
        uint256 lockEnd = ILocker(lockerToMigrate).lockedUntil();
        vm.warp(lockEnd);
        vm.roll(block.number + 1);
        vm.expectRevert(ILockerFactory.NotLocked.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: 0,
            _unlock1Min: 0,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    modifier whenTheLockerHasNotExpired() {
        _;
    }

    function test_WhenTheAmountsToUnlockAreSmallerThanTheAmountsToMigrate()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
    {
        // It should revert with {InsufficientUnlockMin}
        vm.expectRevert(ILockerFactory.InsufficientUnlock0Min.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: 0,
            _unlock1Min: 0,
            _amount0Min: 1,
            _amount1Min: 0
        });

        vm.expectRevert(ILockerFactory.InsufficientUnlock1Min.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: 0,
            _unlock1Min: 0,
            _amount0Min: 0,
            _amount1Min: 1
        });
    }

    modifier whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate() {
        _;
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should revert with {InsufficientAmountUnlocked}

        // create pool launcher pool in new pool launcher with different price to simulate slippage
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount * 2,
            amountPoolLauncherTokenMin: poolLauncherAmount,
            amountTokenToPairMin: usdcAmount * 2,
            lockDuration: 86400
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, poolLauncherAmount);
        deal(tokenToPair, users.alice, usdcAmount * 2);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        usdc.approve(address(v2PoolLauncher), usdcAmount * 2);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        vm.expectRevert(IV2LockerFactory.InsufficientAmount0Unlocked.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            /// @dev Increment amount unlocked by 1 to simulate insufficient amount
            _unlock0Min: amountToken0 - 1e10 + 1,
            _unlock1Min: amountToken1 - 1,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock_Token1()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should revert with {InsufficientAmountUnlocked}

        // create pool launcher pool in new pool launcher with different price to simulate slippage
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount * 2,
            amountPoolLauncherTokenMin: poolLauncherAmount,
            amountTokenToPairMin: usdcAmount * 2,
            lockDuration: 86400
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, poolLauncherAmount);
        deal(tokenToPair, users.alice, usdcAmount * 2);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        usdc.approve(address(v2PoolLauncher), usdcAmount * 2);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        vm.expectRevert(IV2LockerFactory.InsufficientAmount1Unlocked.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: amountToken0 - 1e10,
            /// @dev Increment amount unlocked by 1 to simulate insufficient amount
            _unlock1Min: amountToken1,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    modifier whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock() {
        _;
    }

    function test_WhenTheAmountsMigratedAreSmallerThanTheMinAmounts()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
    {
        // It should revert with {InsufficientAmount}

        // create pool launcher pool in new pool launcher with different price to simulate slippage
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount * 2,
            amountPoolLauncherTokenMin: poolLauncherAmount,
            amountTokenToPairMin: usdcAmount * 2,
            lockDuration: 86400
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, poolLauncherAmount);
        deal(tokenToPair, users.alice, usdcAmount * 2);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        usdc.approve(address(v2PoolLauncher), usdcAmount * 2);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        vm.expectRevert(IV2Router.InsufficientAmountA.selector);
        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: amountToken0 - 1e10,
            _unlock1Min: amountToken1 - 1,
            _amount0Min: poolLauncherAmount / 2,
            _amount1Min: usdcAmount - 1
        });
    }

    function test_WhenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
    {
        // It should decrease the locked amount stored in the factory
        // It should decrease the number of locks stored in the factory
        // It should remove the reference to the locker in the factory
        // It should migrate the locker to the new locker factory
        // It should refund any leftover tokens to the new locker
        // It should emit a {LockerUnlocked} event
        // It should emit a {Migrate} event

        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        deal(address(usdc), lockerToMigrate, USDC_1);
        deal(address(token), lockerToMigrate, TOKEN_1);

        /// @dev Mint additional LP to ensure Alice does not hold the entire supply
        vm.startPrank(users.bob);
        uint256 reserveLauncher = token.balanceOf(v2Pool);
        uint256 reserveUSDC = usdc.balanceOf(v2Pool);
        deal(address(token), users.bob, reserveLauncher / 100);
        deal(address(usdc), users.bob, reserveUSDC / 100);
        token.transfer({to: v2Pool, value: reserveLauncher / 100});
        usdc.transfer({to: v2Pool, value: reserveUSDC / 100});
        IV2Pool(v2Pool).mint({to: users.bob});
        vm.stopPrank();

        // create pool launcher pool in new pool launcher with different price to simulate slippage
        vm.startPrank(users.alice);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount * 2,
            amountPoolLauncherTokenMin: poolLauncherAmount,
            amountTokenToPairMin: usdcAmount * 2,
            lockDuration: 86400
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, poolLauncherAmount);
        deal(tokenToPair, users.alice, usdcAmount * 2);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        usdc.approve(address(v2PoolLauncher), usdcAmount * 2);
        (IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool, address newLockerAddress0) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        address newPool = newPoolLauncherPool.pool;
        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: poolLauncherToken, tokenB: tokenToPair, stable: false});
        assertEq(newPool, predictedUnderlyingPool);

        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 2});
        vm.expectCall(lockerToMigrate, abi.encodeCall(ILocker.unlock, (poolToMigrate, address(oldV2LockerFactory))));
        vm.expectEmit({emitter: address(oldV2LockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: lockerToMigrate,
            underlyingPool: poolToMigrate,
            recipient: poolToMigrate,
            refundAddress: address(oldV2LockerFactory)
        });
        vm.expectEmit(address(oldV2LockerFactory));
        emit ILockerFactory.LockerMigrated({
            oldLocker: lockerToMigrate,
            newLocker: predictedLocker,
            lp: 999999999999999000
        });

        (uint256 amount0, uint256 amount1, address newLockerAddress) = oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: amountToken0 - 1e10,
            _unlock1Min: usdcAmount - 1,
            _amount0Min: poolLauncherAmount / 2 - 1e14,
            _amount1Min: usdcAmount - 1
        });

        (uint256 expectedAmount0, uint256 expectedAmount1) = poolLauncherToken < tokenToPair
            ? (poolLauncherAmount - 1e10, usdcAmount - 1)
            : (usdcAmount - 1, poolLauncherAmount - 1e10); // account for MINIMUM_LIQUIDITY

        assertEq(amount0, expectedAmount0);
        assertEq(amount1, expectedAmount1);
        assertEq(oldV2LockerFactory.locked({_pool: poolToMigrate}), 0);
        assertEq(oldV2LockerFactory.locked({_pool: newPool}), 0);
        assertEq(v2LockerFactory.locked({_pool: poolToMigrate}), 0);
        assertEq(v2LockerFactory.locked({_pool: newPool}), 2121320343552570504);

        assertEq(oldV2LockerFactory.locks({_pool: poolToMigrate}), 0);
        assertEq(oldV2LockerFactory.locks({_pool: newPool}), 0);
        assertEq(v2LockerFactory.locks({_pool: poolToMigrate}), 0);
        assertEq(v2LockerFactory.locks({_pool: newPool}), 2);

        assertFalse(oldV2LockerFactory.instances({_locker: lockerToMigrate}));
        assertTrue(v2LockerFactory.instances({_locker: newLockerAddress}));

        /// @dev Assert new locker state
        IV2Locker newLocker = IV2Locker(newLockerAddress);
        assertEq(Ownable(newLockerAddress).owner(), users.alice);
        assertEq(newLocker.router(), v2Router);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(v2LockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.BASIC));

        assertEq(newLocker.pool(), newPool);
        assertEq(newLocker.token0(), address(token));
        assertEq(newLocker.token1(), address(usdc));
        assertEq(newLocker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(newLocker.beneficiary(), users.bob);
        assertEq(newLocker.beneficiaryShare(), beneficiaryShare);
        assertFalse(newLocker.root());

        assertEq(address(newLocker.gauge()), address(0));
        assertEq(newLocker.bribeableShare(), bribeableShare);
        assertEq(newLocker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(newLocker.staked());

        assertEq(IV2Pool(newPool).balanceOf(address(newLocker)), newLocker.lp());
        assertEq(IV2Pool(newPool).balanceOf(users.alice), 0);

        /// @dev Ensure leftovers from slippage and old locker balance are sent to the new locker
        assertGt(token.balanceOf(newPool), 0);
        assertGt(usdc.balanceOf(newPool), 0);
        assertApproxEqAbs(token.balanceOf(address(newLocker)), poolLauncherAmount / 2 + TOKEN_1, 1e14);
        assertEq(usdc.balanceOf(address(newLocker)), USDC_1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);

        /// @dev Ensure no outstanding allowances
        assertEq(IERC20(newPool).allowance({owner: address(oldV2LockerFactory), spender: address(v2LockerFactory)}), 0);
        assertEq(usdc.allowance({owner: address(oldV2LockerFactory), spender: v2LockerFactory.v2Router()}), 0);
        assertEq(token.allowance({owner: address(oldV2LockerFactory), spender: v2LockerFactory.v2Router()}), 0);

        locker = IV2Locker(newLockerAddress0);
        v2Pool = newPool;
        _assertMappings(2, newLockerAddress, address(0));
    }

    function testGas_migrate()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerIsAValidInstance
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock
    {
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: poolLauncherAmount,
            amountTokenToPairMin: usdcAmount,
            lockDuration: 86400
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, poolLauncherAmount);
        deal(tokenToPair, users.alice, usdcAmount);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        usdc.approve(address(v2PoolLauncher), usdcAmount);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        oldV2LockerFactory.migrate({
            _locker: lockerToMigrate,
            _unlock0Min: amountToken0 - 1e10,
            _unlock1Min: usdcAmount - 1,
            _amount0Min: poolLauncherAmount / 2 - 1e14,
            _amount1Min: usdcAmount - 1
        });

        vm.snapshotGasLastCall("V2LockerFactory_migrate");
    }
}
