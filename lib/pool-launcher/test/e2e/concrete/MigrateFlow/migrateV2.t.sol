// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../../../BaseForkFixture.sol";

contract MigrateV2E2ETest is BaseForkFixture {
    using stdStorage for StdStorage;

    V2PoolLauncher public oldV2PoolLauncher;
    V2LockerFactory public oldV2LockerFactory;
    IV2PoolLauncher.PoolLauncherPool public poolToMigrate;
    address public lockerToMigrate;

    function setUp() public virtual override {
        super.setUp();

        oldV2PoolLauncher = v2PoolLauncher;
        oldV2LockerFactory = v2LockerFactory;

        uint256 amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 amountTokenToPair = 1000 * USDC_1;
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

        vm.prank(IVoter(voter).governor());
        IVoter(voter).createGauge({poolFactory: v2Factory, pool: poolToMigrate.pool});

        // deploy new poolLauncher and locker factory
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

    function test_UnstakeAndMigrate() external {
        vm.prank(users.owner);
        oldV2PoolLauncher.setNewPoolLauncher({_newPoolLauncher: address(v2PoolLauncher)});
        vm.startPrank(users.alice);

        ILocker(lockerToMigrate).stake();
        vm.expectRevert(); // Need to unstake before migrating
        oldV2PoolLauncher.migrate({
            _locker: lockerToMigrate,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });

        ILocker(lockerToMigrate).unstake();

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
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });

        assertEq(IERC20(poolToMigrate.pool).balanceOf(lockerToMigrate), 0);
        assertEq(ILocker(lockerToMigrate).lockedUntil(), 0);

        assertEq(IERC20(newPoolLauncherPool.pool).balanceOf(lockerToMigrate), 0);
        assertEq(uint8(ILocker(newLocker).poolType()), uint8(ILockerFactory.PoolType.BASIC));

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: address(token), tokenB: address(usdc), stable: false});
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        assertNotEq(newPoolLauncherPool.pool, address(0));
        assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newLocker, predictedLocker);
        assertEq(
            newPoolLauncherPool.pool,
            v2PoolLauncher.getPool({_tokenA: address(token), _tokenB: address(usdc), _stable: false})
        );
        assertEq(
            newPoolLauncherPool.pool,
            v2PoolLauncher.getPool({_tokenA: address(usdc), _tokenB: address(token), _stable: false})
        );

        assertEq(IERC20(newPoolLauncherPool.pool).balanceOf(newLocker), 999999999498499);
        assertEq(ILocker(newLocker).lockedUntil(), block.timestamp + (365 days / 2));
        assertEq(uint8(ILocker(newLocker).poolType()), uint8(ILockerFactory.PoolType.BASIC));

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
    }
}
