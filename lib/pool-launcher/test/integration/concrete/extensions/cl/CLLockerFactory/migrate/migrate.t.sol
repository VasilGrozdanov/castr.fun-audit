// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLockerFactory.t.sol";

contract MigrateIntegrationConcreteTest is CLLockerFactoryTest {
    using stdStorage for StdStorage;
    using SafeERC20 for IERC20;

    uint16 public constant beneficiaryShare = 500;
    uint16 public constant bribeableShare = 1_000;
    uint256 public depositedPoolLauncherAmount;
    uint256 public depositedUsdcAmount;

    // CL PoolLauncher contracts
    CLLockerFactory public newCLLockerFactory;
    CLPoolLauncher public newCLPoolLauncher;
    address public newNfpManager;
    address public newPool;

    uint256 public oldLP;
    address public oldPool;
    address public oldLocker;
    uint128 public lockedLiquidity;
    uint256 public newPoolLiquidity;

    function parsedAddresses() internal view override returns (string memory) {
        string memory root = vm.projectRoot();
        string memory path = string(abi.encodePacked(root, "/test/e2e/addresses-op.json"));
        return vm.readFile(path);
    }

    function setUp() public virtual override {
        vm.createSelectFork({urlOrAlias: "optimism", blockNumber: 140500000});
        BaseFixture.setUp();

        poolLauncherAmount = TOKEN_1 * 1_000_000;
        usdcAmount = USDC_1 * 1_000_000;

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

    function test_InitialState() public view override {
        assertEq(clLockerFactory.owner(), users.owner);
        assertEq(address(clLockerFactory.nfpManager()), nfpManager);
        assertEq(address(clLockerFactory.clFactory()), clFactory);
        assertEq(clLockerFactory.MAX_BPS(), MAX_BPS);
        assertEq(clLockerFactory.voter(), voter);
        assertEq(clLockerFactory.poolLauncher(), address(clPoolLauncher));
        assertEq(uint8(clLockerFactory.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(clLockerFactory.newLockerFactory(), address(0));
    }

    function test_WhenTheNewLockerFactoryIsNotSet() external {
        // It should revert with {MigrationDisabled}
        vm.prank(users.alice);
        vm.expectRevert(ILockerFactory.MigrationDisabled.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheNewLockerFactoryIsSet() {
        vm.prank(clLockerFactory.owner());
        clLockerFactory.setNewLockerFactory({_lockerFactory: address(newCLLockerFactory)});
        _;
    }

    function test_WhenTheLockerDoesNotExist() external whenTheNewLockerFactoryIsSet {
        // It should revert with {NotLocker}
        address _locker = address(0);

        vm.prank(users.alice);
        vm.expectRevert(ILockerFactory.NotLocker.selector);
        clLockerFactory.migrate({_locker: _locker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheLockerExists() {
        _;
    }

    modifier whenTheCallerIsThePoolLauncher() {
        vm.startPrank(address(clPoolLauncher));
        _;
    }

    function test_WhenTheAmountsToUnlockAreSmallerThanTheAmountsToMigrate()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsThePoolLauncher
    {
        // It should revert with {InsufficientUnlockMin}
        vm.expectRevert(ILockerFactory.InsufficientUnlock0Min.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 1, _amount1Min: 0});

        vm.expectRevert(ILockerFactory.InsufficientUnlock1Min.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 1});
    }

    modifier whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate() {
        _;
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsThePoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should revert with {PS}
        vm.expectRevert(bytes("PS"));
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount + 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock_Token1()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsThePoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should revert with {PS}
        vm.expectRevert(bytes("PS"));
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount + 1,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    function test_WhenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsThePoolLauncher
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate
    {
        // It should remove the old locker instance from the factory
        // It should update the liquidity for the underlying pool
        // It should update the lock count for the underlying pool
        // It should unlock the old locker and withdraw all liquidity to the pool launcher
        // It should burn the old liquidity position
        // It should return the unlocked token amounts
        // It should emit a {LockerUnlocked} event
        vm.expectCall(oldLocker, abi.encodeCall(ILocker.unlock, (address(clLockerFactory), address(clPoolLauncher))));
        vm.expectEmit({emitter: address(clLockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: oldLocker,
            underlyingPool: oldPool,
            recipient: address(clLockerFactory),
            refundAddress: address(clPoolLauncher)
        });
        (uint256 amount0, uint256 amount1,) = clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: depositedUsdcAmount - 1,
            _amount1Min: depositedPoolLauncherAmount - 1
        });

        assertFalse(clLockerFactory.instances(oldLocker));
        assertEq(clLockerFactory.locked(oldPool), 0);
        assertEq(clLockerFactory.locks(oldPool), 0);

        assertFalse(ICLLocker(oldLocker).staked());
        assertEq(ICLLocker(oldLocker).lockedUntil(), 0);

        assertApproxEqAbs(amount0, depositedUsdcAmount, 1);
        assertApproxEqAbs(amount1, depositedPoolLauncherAmount, 1);
        assertEq(usdc.balanceOf(address(clPoolLauncher)), amount0);
        assertEq(token.balanceOf(address(clPoolLauncher)), amount1);

        /// @dev Ensure no outstanding balances
        assertEq(usdc.balanceOf(address(clLockerFactory)), 0);
        assertEq(token.balanceOf(address(clLockerFactory)), 0);

        /// @dev Previous LP was burnt
        vm.expectRevert("ERC721: owner query for nonexistent token");
        IERC721(nfpManager).ownerOf({tokenId: oldLP});

        _assertMappings(0, address(0), address(0));
    }

    modifier whenTheCallerIsNotThePoolLauncher() {
        /// @dev Launch identical pool on new pool factory
        ICLFactory newCLFactory = newCLPoolLauncher.clFactory();

        vm.startPrank(users.alice);
        usdc.approve(address(newCLFactory), usdcAmount);
        token.approve(address(newCLFactory), poolLauncherAmount);
        newPool = newCLFactory.createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            sqrtPriceX96: encodePriceSqrt({reserve1: 1e12, reserve0: 1})
        });

        /// @dev Create Locker with custom parameters
        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);
        usdc.safeIncreaseAllowance({spender: address(nfpManager), value: usdcAmount});
        token.safeIncreaseAllowance({spender: address(nfpManager), value: poolLauncherAmount});

        (oldLP,,,) = INfpm(nfpManager).mint({
            params: INfpm.MintParams({
                token0: address(usdc),
                token1: address(token),
                tickSpacing: TICK_SPACING_200,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: usdcAmount,
                amount1Desired: poolLauncherAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: users.alice,
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        });
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: oldLP});
        oldLocker = clLockerFactory.lock({
            _lp: oldLP,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare,
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
        vm.stopPrank();
        _;
    }

    function test_WhenTheCallerIsNotTheOwner()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher
    {
        // It should revert with {NotLockerOwnerOrPoolLauncher}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(ILockerFactory.NotLockerOwnerOrPoolLauncher.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerIsNotLocked()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher
        whenTheCallerIsTheOwner
    {
        // It should revert with {NotLocked}
        skip(lockDuration);
        vm.expectRevert(ILockerFactory.NotLocked.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheLockerIsLocked() {
        _;
    }

    function test_WhenTheAmountsToUnlockAreSmallerThanTheAmountsToMigrate_()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
    {
        // It should revert with {InsufficientUnlockMin}
        vm.expectRevert(ILockerFactory.InsufficientUnlock0Min.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 1, _amount1Min: 0});

        vm.expectRevert(ILockerFactory.InsufficientUnlock1Min.selector);
        clLockerFactory.migrate({_locker: oldLocker, _unlock0Min: 0, _unlock1Min: 0, _amount0Min: 0, _amount1Min: 1});
    }

    modifier whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate_() {
        _;
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock_()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate_
    {
        // It should revert with {PS}
        vm.expectRevert(bytes("PS"));
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount + 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    function test_WhenTheAmountsUnlockedAreSmallerThanTheMinAmountsToUnlock_Token1_()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate_
    {
        // It should revert with {PS}
        vm.expectRevert(bytes("PS"));
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount + 1,
            _amount0Min: 0,
            _amount1Min: 0
        });
    }

    modifier whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock_() {
        _;
    }

    function test_WhenTheAmountsMigratedAreSmallerThanTheMinAmounts()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher_RefundFlow
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate_
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock_
    {
        // It should revert with {PSC}
        vm.expectRevert(bytes("PSC"));
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: depositedUsdcAmount / 2 + 1,
            _amount1Min: depositedPoolLauncherAmount - 1e6
        });
    }

    function test_WhenTheAmountsMigratedAreSmallerThanTheMinAmounts_Token1()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher_RefundFlow
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate_
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock_
    {
        // It should revert with {PSC}
        vm.expectRevert(bytes("PSC"));
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: depositedUsdcAmount / 2,
            _amount1Min: depositedPoolLauncherAmount - 1
        });
    }

    function test_WhenTheAmountsMigratedAreGreaterThanOrEqualToTheMinAmounts()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenTheAmountsToUnlockAreGreaterThanOrEqualToTheAmountsToMigrate_
        whenTheAmountsUnlockedAreGreaterThanOrEqualToTheMinAmountsToUnlock_
    {
        // It should remove the old locker instance from the factory
        // It should update the liquidity for the underlying pool
        // It should update the lock count for the underlying pool
        // It should unlock the old locker and withdraw all liquidity
        // It should burn the old liquidity position
        // It should mint a liquidity position on the new deployment
        // It should refund any leftover tokens to the new locker
        // It should reset any outstanding allowances
        // It should lock the LP in an identical locker in the new factory
        // It should return the unlocked token amounts
        // It should emit a {LockerUnlocked} event
        // It should emit a {LockerMigrated} event
        address newLocker = predictLockerAddress({lockerFactory: address(newCLLockerFactory), nonce: 1});
        (,,,,,,, uint256 lockerLiq,,,,) = INfpm(nfpManager).positions({tokenId: oldLP});
        uint256 oldLocked = clLockerFactory.locked(oldPool);

        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        uint256 oldLeftoverUSDC = USDC_1;
        uint256 oldLeftoverLauncherToken = TOKEN_1;
        deal(address(usdc), oldLocker, oldLeftoverUSDC);
        deal(address(token), oldLocker, oldLeftoverLauncherToken);

        vm.expectCall(oldLocker, abi.encodeCall(ILocker.unlock, (address(clLockerFactory), address(clLockerFactory))));
        vm.expectEmit({emitter: address(clLockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: oldLocker,
            underlyingPool: oldPool,
            recipient: address(clLockerFactory),
            refundAddress: address(clLockerFactory)
        });
        vm.expectEmit({
            checkTopic1: true,
            checkTopic2: true,
            checkTopic3: false,
            checkData: false,
            emitter: address(clLockerFactory)
        });
        emit ILockerFactory.LockerMigrated({oldLocker: oldLocker, newLocker: newLocker, lp: 0});
        (uint256 amount0, uint256 amount1,) = clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: depositedUsdcAmount - 1,
            _amount1Min: depositedPoolLauncherAmount - 1e12
        });
        assertFalse(clLockerFactory.instances(oldLocker));
        assertEq(clLockerFactory.locked(oldPool), oldLocked - lockerLiq);
        assertEq(clLockerFactory.locks(oldPool), 1);

        assertFalse(ICLLocker(oldLocker).staked());
        assertEq(ICLLocker(oldLocker).lockedUntil(), 0);

        /// @dev Previous LP was burnt
        vm.expectRevert("ERC721: owner query for nonexistent token");
        IERC721(nfpManager).ownerOf({tokenId: oldLP});

        uint256 lp = ILocker(newLocker).lp();
        (,, address token0, address token1, int24 tickSpacingLP, int24 tickLowerLP, int24 tickUpperLP,,,,,) =
            INfpm(newNfpManager).positions({tokenId: lp});
        assertEq(token0, address(usdc));
        assertEq(token1, address(token));
        assertEq(tickLower, tickLowerLP);
        assertEq(tickUpper, tickUpperLP);
        assertEq(TICK_SPACING_200, tickSpacingLP);

        /// @dev Assert new locker state
        locker = ICLLocker(newLocker);
        assertEq(Ownable(newLocker).owner(), users.alice);
        assertEq(address(locker.nfpManager()), newNfpManager);

        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(newCLLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(locker.pool(), newPool);
        assertEq(locker.token0(), address(usdc));
        assertEq(locker.token1(), address(token));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.beneficiary(), users.bob);
        assertEq(locker.beneficiaryShare(), beneficiaryShare);
        assertTrue(locker.root());

        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), bribeableShare);
        assertEq(locker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(locker.staked());

        assertEq(INfpm(newNfpManager).ownerOf(locker.lp()), address(locker));

        /// @dev Assert deposited amounts
        assertApproxEqAbs(amount0, depositedUsdcAmount, 1);
        assertApproxEqAbs(amount1, depositedPoolLauncherAmount, 1);

        /// @dev Ensure no outstanding balances or allowances in LockerFactory
        assertEq(usdc.balanceOf(address(clLockerFactory)), 0);
        assertEq(token.balanceOf(address(clLockerFactory)), 0);
        assertEq(usdc.allowance(address(clLockerFactory), newNfpManager), 0);
        assertEq(token.allowance(address(clLockerFactory), newNfpManager), 0);
        assertEq(usdc.allowance(address(clLockerFactory), address(nfpManager)), 0);
        assertEq(token.allowance(address(clLockerFactory), address(nfpManager)), 0);

        assertTrue(newCLLockerFactory.instances(newLocker));
        assertApproxEqAbs(newCLLockerFactory.locked(newPool), lockedLiquidity, 1e6);
        assertEq(newCLLockerFactory.locks(newPool), 1);

        /// @dev Refunds leftover from slippage and old locker balance to new locker
        assertGt(token.balanceOf(newPool), 0);
        assertGt(usdc.balanceOf(newPool), 0);
        assertApproxEqAbs(
            token.balanceOf(newLocker),
            depositedPoolLauncherAmount + oldLeftoverLauncherToken - token.balanceOf(newPool),
            1
        );
        assertApproxEqAbs(usdc.balanceOf(newLocker), depositedUsdcAmount + oldLeftoverUSDC - usdc.balanceOf(newPool), 1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);

        clPool = newPool;
        clLockerFactory = newCLLockerFactory;
        locker = ICLLocker(newLocker);
        _assertMappings(1, address(0), address(0));
    }

    modifier whenTheCallerIsNotThePoolLauncher_RefundFlow() {
        /// @dev Launch identical pool on new pool factory
        ICLFactory newCLFactory = newCLPoolLauncher.clFactory();

        vm.startPrank(users.alice);
        usdc.approve(address(newCLFactory), usdcAmount);
        token.approve(address(newCLFactory), poolLauncherAmount);
        newPool = newCLFactory.createPool({
            tokenA: address(token),
            tokenB: address(usdc),
            tickSpacing: TICK_SPACING_200,
            /// @dev Use slightly different price to simulate slippage
            sqrtPriceX96: encodePriceSqrt({reserve1: 2e12, reserve0: 1})
        });

        /// @dev Create Locker with custom parameters
        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);
        usdc.safeIncreaseAllowance({spender: address(nfpManager), value: usdcAmount});
        token.safeIncreaseAllowance({spender: address(nfpManager), value: poolLauncherAmount});

        (oldLP,,,) = INfpm(nfpManager).mint({
            params: INfpm.MintParams({
                token0: address(usdc),
                token1: address(token),
                tickSpacing: TICK_SPACING_200,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: usdcAmount,
                amount1Desired: poolLauncherAmount,
                amount0Min: 0,
                amount1Min: 0,
                recipient: users.alice,
                deadline: block.timestamp,
                sqrtPriceX96: 0
            })
        });
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: oldLP});
        oldLocker = clLockerFactory.lock({
            _lp: oldLP,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare,
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
        vm.stopPrank();
        _;
    }

    function test_WhenTheLockerIsLocked_RefundFlow()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher_RefundFlow
        whenTheCallerIsTheOwner
    {
        // It should remove the old locker instance from the factory
        // It should update the liquidity for the underlying pool
        // It should update the lock count for the underlying pool
        // It should unlock the old locker and withdraw all liquidity
        // It should burn the old liquidity position
        // It should mint a liquidity position on the new deployment
        // It should refund any leftover tokens to the new locker
        // It should reset any outstanding allowances
        // It should lock the LP in an identical locker in the new factory
        // It should return the unlocked token amounts
        // It should emit a {LockerUnlocked} event
        // It should emit a {LockerMigrated} event
        address newLocker = predictLockerAddress({lockerFactory: address(newCLLockerFactory), nonce: 1});
        (,,,,,,, uint256 lockerLiq,,,,) = INfpm(nfpManager).positions({tokenId: oldLP});
        uint256 oldLocked = clLockerFactory.locked(oldPool);

        /// @dev Reset Alice's balances
        deal(address(usdc), users.alice, 0);
        deal(address(token), users.alice, 0);

        /// @dev Seed old Locker with additional leftovers, to test locker balance refunds
        uint256 oldLeftoverUSDC = USDC_1;
        uint256 oldLeftoverLauncherToken = TOKEN_1;
        deal(address(usdc), oldLocker, oldLeftoverUSDC);
        deal(address(token), oldLocker, oldLeftoverLauncherToken);

        vm.expectCall(oldLocker, abi.encodeCall(ILocker.unlock, (address(clLockerFactory), address(clLockerFactory))));
        vm.expectEmit({emitter: address(clLockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: oldLocker,
            underlyingPool: oldPool,
            recipient: address(clLockerFactory),
            refundAddress: address(clLockerFactory)
        });
        vm.expectEmit({
            checkTopic1: true,
            checkTopic2: true,
            checkTopic3: false,
            checkData: false,
            emitter: address(clLockerFactory)
        });
        emit ILockerFactory.LockerMigrated({oldLocker: oldLocker, newLocker: newLocker, lp: 0});
        (uint256 amount0, uint256 amount1,) = clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: depositedUsdcAmount / 2,
            _amount1Min: depositedPoolLauncherAmount - 1e6
        });

        assertFalse(clLockerFactory.instances(oldLocker));
        assertEq(clLockerFactory.locked(oldPool), oldLocked - lockerLiq);
        assertEq(clLockerFactory.locks(oldPool), 1);

        assertFalse(ICLLocker(oldLocker).staked());
        assertEq(ICLLocker(oldLocker).lockedUntil(), 0);

        /// @dev Previous LP was burnt
        vm.expectRevert("ERC721: owner query for nonexistent token");
        IERC721(nfpManager).ownerOf({tokenId: oldLP});

        uint256 lp = ILocker(newLocker).lp();
        (,, address token0, address token1, int24 tickSpacingLP, int24 tickLowerLP, int24 tickUpperLP,,,,,) =
            INfpm(newNfpManager).positions({tokenId: lp});
        assertEq(token0, address(usdc));
        assertEq(token1, address(token));
        assertEq(tickLower, tickLowerLP);
        assertEq(tickUpper, tickUpperLP);
        assertEq(TICK_SPACING_200, tickSpacingLP);

        assertEq(ILocker(newLocker).lockedUntil(), block.timestamp + lockDuration);
        assertEq(ILocker(newLocker).beneficiary(), users.bob);
        assertEq(ILocker(newLocker).beneficiaryShare(), beneficiaryShare);
        assertEq(ILocker(newLocker).bribeableShare(), bribeableShare);
        assertEq(Ownable(newLocker).owner(), users.alice);

        assertApproxEqAbs(amount0, depositedUsdcAmount, 1);
        assertApproxEqAbs(amount1, depositedPoolLauncherAmount, 1);

        /// @dev Ensure no outstanding balances or allowances in LockerFactory
        assertEq(usdc.balanceOf(address(clLockerFactory)), 0);
        assertEq(token.balanceOf(address(clLockerFactory)), 0);
        assertEq(usdc.allowance(address(clLockerFactory), newNfpManager), 0);
        assertEq(token.allowance(address(clLockerFactory), newNfpManager), 0);
        assertEq(usdc.allowance(address(clLockerFactory), address(nfpManager)), 0);
        assertEq(token.allowance(address(clLockerFactory), address(nfpManager)), 0);

        assertTrue(newCLLockerFactory.instances(newLocker));
        assertEq(newCLLockerFactory.locks(newPool), 1);

        /// @dev Liquidity minted for new pool is smaller than original liquidity due to slippage
        assertGt(newCLLockerFactory.locked(newPool), 0);
        assertLt(newCLLockerFactory.locked(newPool), lockerLiq);

        /// @dev Refunds leftover from slippage and old locker balance to new locker
        assertGt(token.balanceOf(newPool), 0);
        assertGt(usdc.balanceOf(newPool), 0);
        assertApproxEqAbs(
            token.balanceOf(newLocker),
            depositedPoolLauncherAmount + oldLeftoverLauncherToken - token.balanceOf(newPool),
            1
        );
        assertApproxEqAbs(usdc.balanceOf(newLocker), depositedUsdcAmount + oldLeftoverUSDC - usdc.balanceOf(newPool), 1);
        assertEq(token.balanceOf(users.alice), 0);
        assertEq(usdc.balanceOf(users.alice), 0);
    }

    function testGas_migrate()
        external
        whenTheNewLockerFactoryIsSet
        whenTheLockerExists
        whenTheCallerIsNotThePoolLauncher_RefundFlow
        whenTheCallerIsTheOwner
    {
        clLockerFactory.migrate({
            _locker: oldLocker,
            _unlock0Min: depositedUsdcAmount - 1,
            _unlock1Min: depositedPoolLauncherAmount - 1,
            _amount0Min: depositedUsdcAmount / 2,
            _amount1Min: depositedPoolLauncherAmount - 1e6
        });
        vm.snapshotGasLastCall("CLLockerFactory_migrate");
    }
}
