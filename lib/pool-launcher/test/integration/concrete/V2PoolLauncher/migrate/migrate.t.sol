// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2PoolLauncher.t.sol";

contract MigrateUnitConcreteTest is V2PoolLauncherTest {
    using stdStorage for StdStorage;

    V2PoolLauncher public oldV2PoolLauncher;
    V2LockerFactory public oldV2LockerFactory;
    IV2PoolLauncher.PoolLauncherPool public poolToMigrate;
    address public lockerToMigrate;
    uint256 public amountTokenToPair;
    uint256 public amountPoolLauncherToken;
    uint256 public depositedPoolLauncherAmount;
    uint256 public depositedTokenToPairAmount;

    function setUp() public virtual override {
        super.setUp();

        oldV2PoolLauncher = v2PoolLauncher;
        oldV2LockerFactory = v2LockerFactory;

        amountPoolLauncherToken = 1000 * TOKEN_1;
        amountTokenToPair = 1000 * USDC_1;
        address poolLauncherToken = address(token);
        address tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: amountPoolLauncherToken,
            amountTokenToPair: amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 365 days / 2
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, amountPoolLauncherToken);
        deal(tokenToPair, users.alice, amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), amountTokenToPair);
        (poolToMigrate, lockerToMigrate) =
            oldV2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();

        depositedPoolLauncherAmount = token.balanceOf(poolToMigrate.pool);
        depositedTokenToPairAmount = usdc.balanceOf(poolToMigrate.pool);

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

        require(
            address(oldV2PoolLauncher.v2Factory()) != address(v2PoolLauncher.v2Factory()),
            "factories should be different"
        );
        vm.startPrank(users.owner);
        v2PoolLauncher.addPairableToken({_token: address(usdc)});
        oldV2LockerFactory.setNewLockerFactory({_lockerFactory: address(v2LockerFactory)});
        vm.stopPrank();
    }

    /// @dev Helper function used to create pool with `poolLauncherToken` as `token0`
    function _setToken1() internal {
        /// @dev Simulate token with larger address
        address newToken = address(uint160(address(usdc)) + 1);
        vm.etch({target: address(newToken), newRuntimeBytecode: address(token).code});
        token = IERC20(newToken);

        amountPoolLauncherToken = 1000 * TOKEN_1;
        amountTokenToPair = 1000 * USDC_1;
        address poolLauncherToken = address(token);
        address tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: amountPoolLauncherToken,
            amountTokenToPair: amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 365 days / 2
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, amountPoolLauncherToken);
        deal(tokenToPair, users.alice, amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(oldV2PoolLauncher), amountPoolLauncherToken);
        usdc.approve(address(oldV2PoolLauncher), amountTokenToPair);
        (poolToMigrate, lockerToMigrate) =
            oldV2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();

        depositedPoolLauncherAmount = token.balanceOf(poolToMigrate.pool);
        depositedTokenToPairAmount = usdc.balanceOf(poolToMigrate.pool);
        vm.stopPrank();
    }

    function _seedOldLockerBalance() internal {
        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        deal(address(usdc), lockerToMigrate, USDC_1);
        deal(address(token), lockerToMigrate, TOKEN_1);

        /// @dev Mint additional LP to ensure Alice does not hold the entire supply
        vm.startPrank(users.bob);
        uint256 reserveLauncher = token.balanceOf(poolToMigrate.pool);
        uint256 reserveUSDC = usdc.balanceOf(poolToMigrate.pool);
        deal(address(token), users.bob, reserveLauncher / 100);
        deal(address(usdc), users.bob, reserveUSDC / 100);
        token.transfer({to: poolToMigrate.pool, value: reserveLauncher / 100});
        usdc.transfer({to: poolToMigrate.pool, value: reserveUSDC / 100});
        IV2Pool(poolToMigrate.pool).mint({to: users.bob});
        vm.stopPrank();
    }

    function test_WhenTheLockerIsTheZeroAddress() external {
        // It should revert with {InvalidLocker}
        vm.expectRevert(IPoolLauncher.InvalidLocker.selector);
        oldV2PoolLauncher.migrate({
            _locker: address(0),
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheLockerIsNotTheZeroAddress() {
        _;
    }

    function test_WhenTheNewPoolLauncherIsNotSet() external whenTheLockerIsNotTheZeroAddress {
        // It should revert with {NewPoolLauncherNotSet}
        vm.expectRevert(IPoolLauncher.NewPoolLauncherNotSet.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheNewPoolLauncherIsSet() {
        vm.prank(users.owner);
        oldV2PoolLauncher.setNewPoolLauncher({_newPoolLauncher: address(v2PoolLauncher)});
        _;
    }

    function test_WhenTheCallerIsNotTheLockerOwner()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
    {
        // It should revert with {NotLockerOwner}
        vm.prank(users.charlie);
        vm.expectRevert(IPoolLauncher.NotLockerOwner.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
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

    function test_WhenTheLockerHasExpired()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
    {
        // It should revert with {NotLocked}
        uint256 lockEnd = ILocker(lockerToMigrate).lockedUntil();
        vm.warp(lockEnd);
        vm.roll(block.number + 1);
        vm.expectRevert(IPoolLauncher.NotLocked.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
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
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
    {
        // It should revert with {PoolNotInPoolLauncher}

        /// @dev Create new token with no pool registered in launcher
        token = IERC20(new BasicERC20("Token", "TKN", 100 ether));
        deal(address(usdc), users.alice, amountTokenToPair);
        deal(address(token), users.alice, amountPoolLauncherToken);

        address poolAddr = IV2Factory(oldV2PoolLauncher.v2Factory()).createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            stable: false
        });
        token.transfer({to: poolAddr, value: amountPoolLauncherToken});
        usdc.transfer({to: poolAddr, value: amountTokenToPair});
        uint256 lp = IV2Pool(poolAddr).mint({to: users.alice});
        IERC20(poolAddr).approve({spender: address(oldV2LockerFactory), value: lp});
        lockerToMigrate = oldV2LockerFactory.lock({
            _pool: poolAddr,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + 365 days / 2),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 500,
            _owner: users.alice
        });

        vm.expectRevert(IPoolLauncher.PoolNotInPoolLauncher.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
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
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
    {
        // It should revert with {InsufficientPoolLauncherUnlockMin}
        vm.expectRevert(IPoolLauncher.InsufficientPoolLauncherUnlockMin.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 1,
            _tokenToPairAmountMin: 0
        });

        vm.expectRevert(IPoolLauncher.InsufficientTokenToPairUnlockMin.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 1
        });
    }

    modifier whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate() {
        _;
    }

    function test_WhenTheAmount0UnlockedIsSmallerThanTheMinAmount0ToUnlock()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should revert with {InsufficientAmount0Unlocked}
        vm.expectRevert(IV2LockerFactory.InsufficientAmount0Unlocked.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9 + 1,
            _tokenToPairUnlockMin: amountTokenToPair - 1,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock() {
        _;
    }

    function test_WhenTheAmount1UnlockedIsSmallerThanTheMinAmount1ToUnlock()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock
    {
        // It should revert with {InsufficientAmount1Unlocked}
        vm.expectRevert(IV2LockerFactory.InsufficientAmount1Unlocked.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9,
            _tokenToPairUnlockMin: amountTokenToPair,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });
    }

    modifier whenTheAmount1UnlockedIsGreaterThanOrEqualToTheMinAmount1ToUnlock() {
        _;
    }

    function test_WhenTheAmountsMigratedAreSmallerThanTheMinAmounts()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock
        whenTheAmount1UnlockedIsGreaterThanOrEqualToTheMinAmount1ToUnlock
    {
        // It should revert with {InsufficientAmount}
        assertEq(IV2Pool(poolToMigrate.pool).token0(), address(token));

        deal(address(token), users.alice, amountPoolLauncherToken);
        deal(address(usdc), users.alice, amountTokenToPair * 2);
        /// @dev Create unbalanced pool to simulate launch leftovers
        vm.startPrank(users.alice);
        address poolAddr =
            IV2Factory(v2Factory).createPool({tokenA: address(token), tokenB: address(usdc), stable: false});
        token.transfer({to: poolAddr, value: amountPoolLauncherToken});
        usdc.transfer({to: poolAddr, value: amountTokenToPair * 2});
        IV2Pool(poolAddr).mint({to: users.bob});

        vm.expectRevert(IV2Router.InsufficientAmountA.selector);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9,
            _tokenToPairUnlockMin: amountTokenToPair - 1,
            _poolLauncherAmountMin: amountPoolLauncherToken / 2,
            _tokenToPairAmountMin: amountTokenToPair - 1
        });
    }

    modifier whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts() {
        _;
    }

    function test_WhenThePoolLauncherTokenIsToken0()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock
        whenTheAmount1UnlockedIsGreaterThanOrEqualToTheMinAmount1ToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should migrate the pool launcher pool to the new pool launcher
        // It should migrate the locker to the new locker factory
        // It should refund leftover to new locker
        // It should emit a {LockerUnlocked} event
        // It should emit a {Migrate} event
        _seedOldLockerBalance();
        assertEq(IV2Pool(poolToMigrate.pool).token0(), address(token));

        vm.startPrank(users.alice);
        vm.expectCall(lockerToMigrate, abi.encodeCall(ILocker.unlock, (poolToMigrate.pool, address(oldV2PoolLauncher))));
        vm.expectEmit({emitter: address(oldV2LockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: lockerToMigrate,
            underlyingPool: poolToMigrate.pool,
            recipient: poolToMigrate.pool,
            refundAddress: address(oldV2PoolLauncher)
        });
        vm.expectCall(
            address(oldV2LockerFactory),
            abi.encodeCall(
                ILockerFactory.migrate,
                (
                    lockerToMigrate,
                    amountPoolLauncherToken - 1e9,
                    amountTokenToPair - 1,
                    amountPoolLauncherToken - 1e9,
                    amountTokenToPair - 1
                )
            )
        );
        vm.expectEmit(address(oldV2PoolLauncher));
        emit IPoolLauncher.Migrate({
            underlyingPool: poolToMigrate.pool,
            locker: lockerToMigrate,
            newPoolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false}),
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            }),
            newLocker: predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1})
        });
        (IV2PoolLauncher.PoolLauncherPool memory newPoolLauncherPool, address newLocker) = oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9,
            _tokenToPairUnlockMin: amountTokenToPair - 1,
            _poolLauncherAmountMin: amountPoolLauncherToken - 1e9,
            _tokenToPairAmountMin: amountTokenToPair - 1
        });
        address newPool = newPoolLauncherPool.pool;

        assertEq(IERC20(poolToMigrate.pool).balanceOf(lockerToMigrate), 0);
        assertEq(ILocker(lockerToMigrate).lockedUntil(), 0);

        assertEq(IERC20(newPool).balanceOf(lockerToMigrate), 0);
        assertEq(uint8(ILocker(newLocker).poolType()), uint8(ILockerFactory.PoolType.BASIC));

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false});
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        assertNotEq(newPool, address(0));
        assertEq(newPool, predictedUnderlyingPool);
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newLocker, predictedLocker);
        assertEq(newPool, v2PoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _stable: false}));
        assertEq(newPool, v2PoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _stable: false}));

        /// @dev Assert new locker state
        IV2Locker locker = IV2Locker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(locker.router(), v2Router);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(v2LockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.BASIC));

        assertEq(locker.pool(), newPool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertFalse(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), block.timestamp + (365 days / 2));
        assertFalse(locker.staked());

        assertEq(IV2Pool(newPoolLauncherPool.pool).balanceOf(address(locker)), locker.lp());
        assertEq(locker.lp(), 999999999498499);
        assertEq(IV2Pool(newPoolLauncherPool.pool).balanceOf(users.alice), 0);

        IPoolLauncher.PoolLauncherPool memory storedPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(storedPool.createdAt, block.timestamp);
        assertEq(storedPool.pool, predictedUnderlyingPool);

        assertEq(
            IERC20(poolToMigrate.pool).allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}),
            0
        );
        assertEq(token.allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}), 0);
        assertEq(usdc.allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}), 0);

        /// @dev Ensure leftovers old locker balance are sent to the new locker
        assertGt(token.balanceOf(newPool), 0);
        assertGt(usdc.balanceOf(newPool), 0);
        assertEq(token.balanceOf(newLocker), TOKEN_1);
        assertEq(usdc.balanceOf(newLocker), USDC_1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function test_WhenThePoolLauncherTokenIsToken0_RefundFlow()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock
        whenTheAmount1UnlockedIsGreaterThanOrEqualToTheMinAmount1ToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should migrate the pool launcher pool to the new pool launcher
        // It should migrate the locker to the new locker factory
        // It should refund leftover to new locker
        // It should emit a {LockerUnlocked} event
        // It should emit a {Migrate} event
        _seedOldLockerBalance();
        assertEq(IV2Pool(poolToMigrate.pool).token0(), address(token));

        deal(address(token), users.alice, amountPoolLauncherToken);
        deal(address(usdc), users.alice, amountTokenToPair * 2);
        /// @dev Create unbalanced pool to simulate launch leftovers
        vm.startPrank(users.alice);
        address poolAddr =
            IV2Factory(v2Factory).createPool({tokenA: address(token), tokenB: address(usdc), stable: false});
        token.transfer({to: poolAddr, value: amountPoolLauncherToken});
        usdc.transfer({to: poolAddr, value: amountTokenToPair * 2});
        IV2Pool(poolAddr).mint({to: users.bob});

        vm.expectCall(lockerToMigrate, abi.encodeCall(ILocker.unlock, (poolToMigrate.pool, address(oldV2PoolLauncher))));
        vm.expectEmit({emitter: address(oldV2LockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: lockerToMigrate,
            underlyingPool: poolToMigrate.pool,
            recipient: poolToMigrate.pool,
            refundAddress: address(oldV2PoolLauncher)
        });
        vm.expectCall(
            address(oldV2LockerFactory),
            abi.encodeCall(
                ILockerFactory.migrate,
                (
                    lockerToMigrate,
                    amountPoolLauncherToken - 1e9,
                    amountTokenToPair - 1,
                    amountPoolLauncherToken / 2 - 1e12,
                    amountTokenToPair - 1
                )
            )
        );
        vm.expectEmit(address(oldV2PoolLauncher));
        emit IPoolLauncher.Migrate({
            underlyingPool: poolToMigrate.pool,
            locker: lockerToMigrate,
            newPoolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false}),
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            }),
            newLocker: predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1})
        });
        (IV2PoolLauncher.PoolLauncherPool memory newPoolLauncherPool, address newLocker) = oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9,
            _tokenToPairUnlockMin: amountTokenToPair - 1,
            _poolLauncherAmountMin: amountPoolLauncherToken / 2 - 1e12,
            _tokenToPairAmountMin: amountTokenToPair - 1
        });
        address newPool = newPoolLauncherPool.pool;

        assertEq(IERC20(poolToMigrate.pool).balanceOf(lockerToMigrate), 0);
        assertEq(ILocker(lockerToMigrate).lockedUntil(), 0);

        assertEq(IERC20(newPool).balanceOf(lockerToMigrate), 0);
        assertEq(uint8(ILocker(newLocker).poolType()), uint8(ILockerFactory.PoolType.BASIC));

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false});
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        assertNotEq(newPool, address(0));
        assertEq(newPool, predictedUnderlyingPool);
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newLocker, predictedLocker);
        assertEq(newPool, v2PoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _stable: false}));
        assertEq(newPool, v2PoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _stable: false}));

        /// @dev Assert new locker state
        IV2Locker locker = IV2Locker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(locker.router(), v2Router);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(v2LockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.BASIC));

        assertEq(locker.pool(), newPool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertFalse(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), block.timestamp + (365 days / 2));
        assertFalse(locker.staked());

        assertEq(IV2Pool(newPoolLauncherPool.pool).balanceOf(address(locker)), locker.lp());
        assertEq(locker.lp(), 707106780479440);
        assertEq(IV2Pool(newPoolLauncherPool.pool).balanceOf(users.alice), 0);

        IPoolLauncher.PoolLauncherPool memory storedPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(storedPool.createdAt, block.timestamp);
        assertEq(storedPool.pool, predictedUnderlyingPool);

        assertEq(
            IERC20(poolToMigrate.pool).allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}),
            0
        );
        assertEq(token.allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}), 0);
        assertEq(usdc.allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}), 0);

        /// @dev Ensure leftovers from slippage and old locker balance are sent to the new locker
        assertGt(token.balanceOf(newPool), 0);
        assertGt(usdc.balanceOf(newPool), 0);
        assertApproxEqAbs(token.balanceOf(newLocker), amountPoolLauncherToken / 2 + TOKEN_1, 1e12);
        assertEq(usdc.balanceOf(newLocker), USDC_1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function test_WhenThePoolLauncherTokenIsToken1()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock
        whenTheAmount1UnlockedIsGreaterThanOrEqualToTheMinAmount1ToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should sort the tokens
        // It should migrate the pool launcher pool to the new pool launcher
        // It should migrate the locker to the new locker factory
        // It should refund leftover to new locker
        // It should emit a {LockerUnlocked} event
        // It should emit a {Migrate} event
        _setToken1();
        _seedOldLockerBalance();
        assertEq(IV2Pool(poolToMigrate.pool).token1(), address(token));

        vm.startPrank(users.alice);
        vm.expectCall(lockerToMigrate, abi.encodeCall(ILocker.unlock, (poolToMigrate.pool, address(oldV2PoolLauncher))));
        vm.expectEmit({emitter: address(oldV2LockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: lockerToMigrate,
            underlyingPool: poolToMigrate.pool,
            recipient: poolToMigrate.pool,
            refundAddress: address(oldV2PoolLauncher)
        });
        vm.expectCall(
            address(oldV2LockerFactory),
            abi.encodeCall(
                ILockerFactory.migrate,
                (
                    lockerToMigrate,
                    amountTokenToPair - 1,
                    amountPoolLauncherToken - 1e9,
                    amountTokenToPair - 1,
                    amountPoolLauncherToken - 1e9
                )
            )
        );
        vm.expectEmit(address(oldV2PoolLauncher));
        emit IPoolLauncher.Migrate({
            underlyingPool: poolToMigrate.pool,
            locker: lockerToMigrate,
            newPoolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false}),
                poolLauncherToken: address(token),
                tokenToPair: address(usdc)
            }),
            newLocker: predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1})
        });
        (IV2PoolLauncher.PoolLauncherPool memory newPoolLauncherPool, address newLocker) = oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9,
            _tokenToPairUnlockMin: amountTokenToPair - 1,
            _poolLauncherAmountMin: amountPoolLauncherToken - 1e9,
            _tokenToPairAmountMin: amountTokenToPair - 1
        });
        address newPool = newPoolLauncherPool.pool;

        assertEq(IERC20(poolToMigrate.pool).balanceOf(lockerToMigrate), 0);
        assertEq(ILocker(lockerToMigrate).lockedUntil(), 0);

        assertEq(IERC20(newPool).balanceOf(lockerToMigrate), 0);
        assertEq(uint8(ILocker(newLocker).poolType()), uint8(ILockerFactory.PoolType.BASIC));

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false});
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        assertNotEq(newPool, address(0));
        assertEq(newPool, predictedUnderlyingPool);
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newLocker, predictedLocker);
        assertEq(newPool, v2PoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _stable: false}));
        assertEq(newPool, v2PoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _stable: false}));

        /// @dev Assert new locker state
        IV2Locker locker = IV2Locker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(locker.router(), v2Router);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(v2LockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.BASIC));

        assertEq(locker.pool(), newPool);
        assertEq(locker.token0(), address(usdc));
        assertEq(locker.token1(), address(token));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertFalse(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), block.timestamp + (365 days / 2));
        assertFalse(locker.staked());

        assertEq(IV2Pool(newPoolLauncherPool.pool).balanceOf(address(locker)), locker.lp());
        assertEq(locker.lp(), 999999999498499);
        assertEq(IV2Pool(newPoolLauncherPool.pool).balanceOf(users.alice), 0);

        IPoolLauncher.PoolLauncherPool memory storedPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(storedPool.createdAt, block.timestamp);
        assertEq(storedPool.pool, predictedUnderlyingPool);

        /// @dev Ensure no outstanding allowances
        assertEq(
            IERC20(poolToMigrate.pool).allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}),
            0
        );
        assertEq(token.allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}), 0);
        assertEq(usdc.allowance({owner: address(oldV2PoolLauncher), spender: address(v2PoolLauncher)}), 0);

        assertEq(IERC20(newPool).allowance({owner: address(oldV2LockerFactory), spender: address(v2LockerFactory)}), 0);
        assertEq(usdc.allowance({owner: address(oldV2LockerFactory), spender: v2LockerFactory.v2Router()}), 0);
        assertEq(token.allowance({owner: address(oldV2LockerFactory), spender: v2LockerFactory.v2Router()}), 0);

        /// @dev Ensure leftovers from slippage and old locker balance are sent to the new locker
        assertGt(token.balanceOf(newPool), 0);
        assertGt(usdc.balanceOf(newPool), 0);
        assertEq(token.balanceOf(newLocker), TOKEN_1);
        assertApproxEqAbs(usdc.balanceOf(newLocker), depositedTokenToPairAmount + USDC_1 - usdc.balanceOf(newPool), 1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function testGas_migrate()
        external
        whenTheLockerIsNotTheZeroAddress
        whenTheNewPoolLauncherIsSet
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasNotExpired
        whenTheUnderlyingPoolIsRegisteredInPoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
        whenTheAmount0UnlockedIsGreaterThanOrEqualToTheMinAmount0ToUnlock
        whenTheAmount1UnlockedIsGreaterThanOrEqualToTheMinAmount1ToUnlock
        whenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts
    {
        deal(address(usdc), lockerToMigrate, USDC_1);
        deal(address(token), lockerToMigrate, TOKEN_1);

        vm.startPrank(users.alice);
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: amountPoolLauncherToken - 1e9,
            _tokenToPairUnlockMin: amountTokenToPair - 1,
            _poolLauncherAmountMin: amountPoolLauncherToken - 1e9,
            _tokenToPairAmountMin: amountTokenToPair - 1
        });
        vm.snapshotGasLastCall("V2PoolLauncher_migrate");
    }
}
