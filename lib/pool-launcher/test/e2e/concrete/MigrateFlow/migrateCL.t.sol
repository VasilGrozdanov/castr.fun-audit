// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../../../BaseForkFixture.sol";

contract MigrateCLE2ETest is BaseForkFixture {
    using stdStorage for StdStorage;

    uint256 public constant poolLauncherAmount = TOKEN_1 * 10_000_000;
    uint256 public constant usdcAmount = USDC_1 * 100_000;
    uint32 public constant lockDuration = 86400;
    uint256 public depositedPoolLauncherAmount;
    uint256 public depositedUsdcAmount;

    // CL PoolLauncher contracts
    CLLockerFactory public newCLLockerFactory;
    CLPoolLauncher public newCLPoolLauncher;
    address public newCLFactory;

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

        uint160 sqrtPrice = encodePriceSqrt({reserve1: 1, reserve0: 1});
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
        address newNfpManager = OLD_NFPM_OP;
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

        vm.prank(IVoter(voter).governor());
        IVoter(voter).createGauge({poolFactory: clFactory, pool: oldPool});
    }

    function test_UnstakeAndMigrate() external {
        vm.startPrank(clLockerFactory.owner());
        clPoolLauncher.setNewPoolLauncher({_newPoolLauncher: address(newCLPoolLauncher)});
        clLockerFactory.setNewLockerFactory({_lockerFactory: address(newCLLockerFactory)});
        vm.stopPrank();
        vm.startPrank(users.alice);

        address predictedLocker = predictLockerAddress({lockerFactory: address(newCLLockerFactory), nonce: 1});
        address predictedPool = predictCLPoolAddress({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            factory: address(newCLFactory)
        });
        (,,,,,,, uint128 oldLiquidity,,,,) = INfpm(nfpManager).positions({tokenId: ILocker(oldLocker).lp()});
        (uint160 oldSqrtPrice,,,,,) = ICLPool(oldPool).slot0();

        ILocker(oldLocker).stake();
        vm.expectRevert(); // Need to unstake before migrating
        clPoolLauncher.migrate({
            _locker: oldLocker,
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
        });

        ILocker(oldLocker).unstake();

        vm.expectCall(address(clLockerFactory), abi.encodeCall(ILockerFactory.migrate, (oldLocker, 0, 0, 0, 0)));
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
            _poolLauncherUnlockMin: 0,
            _tokenToPairUnlockMin: 0,
            _poolLauncherAmountMin: 0,
            _tokenToPairAmountMin: 0
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
        assertEq(ILocker(newLocker).pool(), newPool.pool);
        assertEq(ILocker(newLocker).lockedUntil(), block.timestamp + lockDuration);

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
        assertApproxEqAbs(newLiquidity, oldLiquidity, 1);
        (uint160 sqrtPrice,,,,,) = ICLPool(newPool.pool).slot0();
        assertEq(sqrtPrice, oldSqrtPrice);

        /// @dev Ensure no outstanding balances or allowances in poolLauncher contracts
        assertEq(usdc.balanceOf(address(clPoolLauncher)), 0);
        assertEq(token.balanceOf(address(clPoolLauncher)), 0);
        assertEq(usdc.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);
        assertEq(token.allowance(address(clPoolLauncher), address(newCLPoolLauncher)), 0);

        assertEq(usdc.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(token.balanceOf(address(newCLPoolLauncher)), 0);
        assertEq(usdc.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);
        assertEq(token.allowance(address(newCLPoolLauncher), address(nfpManager)), 0);
    }
}
