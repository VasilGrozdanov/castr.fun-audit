// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseForkFixture.sol";

contract V2LockerFactoryTest is BaseForkFixture {
    uint256 public constant poolLauncherAmount = TOKEN_1 * 10_000_000;
    uint256 public constant usdcAmount = USDC_1 * 100_000;
    uint32 public constant lockDuration = 86400;
    address public poolLauncherToken;
    address public tokenToPair;
    uint256 public amountToken0;
    uint256 public amountToken1;

    uint256 public lp;
    address public gauge;
    address public v2Pool;
    IV2Locker public locker;
    /// @dev Signals whether liquidity should be locked in `setUp`
    bool public lockLiquidity = true;

    function setUp() public virtual override {
        super.setUp();

        poolLauncherToken = address(token);
        tokenToPair = address(usdc);
        amountToken0 = address(token) < address(usdc) ? poolLauncherAmount : usdcAmount;
        amountToken1 = address(token) < address(usdc) ? usdcAmount : poolLauncherAmount;

        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        vm.startPrank(users.alice);
        usdc.approve(address(v2PoolLauncher), usdcAmount);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        vm.stopPrank();

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: lockLiquidity ? 86400 : 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: poolLauncherToken,
            tokenToPair: tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(poolLauncherToken, users.alice, poolLauncherAmount);
        deal(tokenToPair, users.alice, usdcAmount);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), poolLauncherAmount);
        usdc.approve(address(v2PoolLauncher), usdcAmount);

        (IPoolLauncher.PoolLauncherPool memory poolLauncherPool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        locker = IV2Locker(lockerAddress);
        v2Pool = poolLauncherPool.pool;
        lp = lockLiquidity ? locker.lp() : IV2Pool(v2Pool).balanceOf(users.alice);
        vm.stopPrank();

        vm.prank(IVoter(voter).governor());
        gauge = IVoter(voter).createGauge({poolFactory: v2Factory, pool: v2Pool});
    }

    function test_InitialState() public virtual {
        assertEq(v2LockerFactory.v2Factory(), v2Factory);
        assertEq(v2LockerFactory.v2Router(), v2Router);

        assertEq(Ownable(v2LockerFactory).owner(), users.owner);
        assertEq(v2LockerFactory.MAX_BPS(), MAX_BPS);
        assertEq(v2LockerFactory.voter(), voter);
        assertEq(uint8(v2LockerFactory.poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(v2LockerFactory.newLockerFactory(), address(0));
        assertEq(v2LockerFactory.poolLauncher(), address(v2PoolLauncher));
        assertEq(IV2Pool(v2Pool).balanceOf(address(locker)), locker.lp());

        _assertMappings(1, address(0), address(0));
    }

    function _assertMappings(uint256 _length, address _newLocker1, address _newLocker2) internal view {
        // @dev assert lockers mapping and view functions
        address[] memory lockers = v2LockerFactory.lockers(v2Pool);
        assertEq(lockers.length, _length);
        if (_length > 0) assertEq(lockers[0], address(locker));
        if (_length > 1) assertEq(lockers[1], _newLocker1);
        if (_length > 2) assertEq(lockers[2], _newLocker2);

        lockers = v2LockerFactory.lockers(v2Pool, 0, _length);
        assertEq(lockers.length, _length);
        if (_length > 0) assertEq(lockers[0], address(locker));
        if (_length > 1) assertEq(lockers[1], _newLocker1);
        if (_length > 2) assertEq(lockers[2], _newLocker2);
        assertEq(v2LockerFactory.lockersCount(v2Pool), _length);

        // @dev assert lockersPerUser mapping and view functions
        address[] memory lockersPerUser = v2LockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerUser[2], _newLocker2);
        lockersPerUser = v2LockerFactory.lockersPerUser(users.alice, 0, _length);
        assertEq(lockersPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerUser[2], _newLocker2);
        assertEq(v2LockerFactory.lockersPerUserCount(users.alice), _length);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        address[] memory lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice);
        assertEq(lockersPerPoolPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerPoolPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerPoolPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerPoolPerUser[2], _newLocker2);
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice, 0, _length);
        assertEq(lockersPerPoolPerUser.length, _length);
        if (_length > 0) assertEq(lockersPerPoolPerUser[0], address(locker));
        if (_length > 1) assertEq(lockersPerPoolPerUser[1], _newLocker1);
        if (_length > 2) assertEq(lockersPerPoolPerUser[2], _newLocker2);
        assertEq(v2LockerFactory.lockersPerPoolPerUserCount(v2Pool, users.alice), _length);
    }
}
