// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../../../../../BaseForkFixture.sol";

abstract contract V2LockerTest is BaseForkFixture {
    uint256 public constant poolLauncherAmount = TOKEN_1 * 10_000_000;
    uint256 public constant usdcAmount = USDC_1 * 100_000;
    uint32 public constant lockDuration = 86400;
    address public poolLauncherToken;
    address public tokenToPair;
    uint256 public amountToken0;
    uint256 public amountToken1;

    uint256 public lp;
    address public v2Pool;
    IV2Locker public locker;
    address public gauge;

    function setUp() public virtual override {
        super.setUp();

        poolLauncherToken = address(token);
        tokenToPair = address(usdc);
        amountToken0 = address(token) < address(usdc) ? poolLauncherAmount : usdcAmount;
        amountToken1 = address(token) < address(usdc) ? usdcAmount : poolLauncherAmount;

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: lockDuration
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
        (IPoolLauncher.PoolLauncherPool memory poolLauncherPool, address _locker) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();

        v2Pool = poolLauncherPool.pool;
        locker = IV2Locker(_locker);
        lp = sqrt(poolLauncherAmount * usdcAmount) - MINIMUM_LIQUIDITY;

        vm.prank(IVoter(voter).governor());
        gauge = IVoter(voter).createGauge({poolFactory: v2Factory, pool: v2Pool});
    }

    function test_InitialState() public view virtual {
        assertEq(Ownable(address(locker)).owner(), users.alice);
        assertEq(locker.MAX_BPS(), MAX_BPS);
        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(v2LockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(locker.pool(), v2Pool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.rewardToken(), IVotingEscrow(MockVoter(voter).ve()).token());
        assertEq(locker.lp(), lp);
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertFalse(locker.root());
        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), block.timestamp + lockDuration);
        assertFalse(locker.staked());
    }
}
