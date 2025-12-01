// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../../../../../BaseForkFixture.sol";

abstract contract CLLockerFactoryTest is BaseForkFixture {
    uint32 public constant lockDuration = 86400;
    uint256 public poolLauncherAmount = TOKEN_1 * 10_000_000;
    uint256 public usdcAmount = USDC_1 * 100_000;
    address public poolLauncherToken;
    address public tokenToPair;
    uint256 public amountToken0;
    uint256 public amountToken1;
    int24 public immutable tickLower = getMinTick({tickSpacing: TICK_SPACING_200});
    int24 public immutable tickUpper = getMaxTick({tickSpacing: TICK_SPACING_200});

    uint256 public lp;
    address public clPool;
    ICLLocker public locker;
    address public gauge;

    function setUp() public virtual override {
        super.setUp();

        poolLauncherToken = address(token);
        tokenToPair = address(usdc);
        amountToken0 = address(token) < address(usdc) ? poolLauncherAmount : usdcAmount;
        amountToken1 = address(token) < address(usdc) ? usdcAmount : poolLauncherAmount;

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
        (IPoolLauncher.PoolLauncherPool memory poolLauncherPool, address _locker) =
            clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});

        clPool = poolLauncherPool.pool;
        locker = ICLLocker(_locker);
        lp = IERC721(nfpManager).tokenOfOwnerByIndex(_locker, 0);

        vm.prank(IVoter(voter).governor());
        gauge = IVoter(voter).createGauge({poolFactory: clFactory, pool: clPool});
    }

    function test_InitialState() public view virtual {
        assertEq(clLockerFactory.owner(), users.owner);
        assertEq(address(clLockerFactory.nfpManager()), nfpManager);
        assertEq(address(clLockerFactory.clFactory()), clFactory);
        assertEq(clLockerFactory.MAX_BPS(), MAX_BPS);
        assertEq(clLockerFactory.voter(), voter);
        assertEq(clLockerFactory.poolLauncher(), address(clPoolLauncher));
        assertEq(uint8(clLockerFactory.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(clLockerFactory.newLockerFactory(), address(0));

        _assertMappings(1, address(0), address(0));
    }

    function _assertMappings(uint256 _length, address _newLocker1, address _newLocker2) internal view {
        // @dev assert lockers mapping and view functions
        address[] memory lockers = clLockerFactory.lockers(clPool);
        assertEq(lockers.length, _length);
        if (_length > 0) assertEq(lockers[0], address(locker));
        if (_length > 1) assertEq(lockers[1], _newLocker1);
        if (_length > 2) assertEq(lockers[2], _newLocker2);

        lockers = clLockerFactory.lockers(clPool, 0, _length);
        assertEq(lockers.length, _length);
        if (_length > 0) assertEq(lockers[0], address(locker));
        if (_length > 1) assertEq(lockers[1], _newLocker1);
        if (_length > 2) assertEq(lockers[2], _newLocker2);
        assertEq(clLockerFactory.lockersCount(clPool), _length);

        // @dev assert lockersPerUser mapping and view functions
        address[] memory lockersPerUser = clLockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerUser[2], _newLocker2);
        lockersPerUser = clLockerFactory.lockersPerUser(users.alice, 0, _length);
        assertEq(lockersPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerUser[2], _newLocker2);
        assertEq(clLockerFactory.lockersPerUserCount(users.alice), _length);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        address[] memory lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, users.alice);
        assertEq(lockersPerPoolPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerPoolPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerPoolPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerPoolPerUser[2], _newLocker2);
        lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, users.alice, 0, _length);
        assertEq(lockersPerPoolPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerPoolPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerPoolPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerPoolPerUser[2], _newLocker2);
        assertEq(clLockerFactory.lockersPerPoolPerUserCount(clPool, users.alice), _length);
    }
}
