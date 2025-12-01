// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../../../../../BaseForkFixture.sol";

abstract contract CLLockerTest is BaseForkFixture {
    uint256 public constant poolLauncherAmount = TOKEN_1 * 10_000_000;
    uint256 public constant usdcAmount = USDC_1 * 100_000;
    uint32 public constant lockDuration = 86400;
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
        assertEq(Ownable(address(locker)).owner(), users.alice);
        assertEq(address(locker.nfpManager()), nfpManager);
        assertEq(locker.MAX_BPS(), MAX_BPS);
        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(clLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(locker.pool(), clPool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.lp(), lp);
        assertEq(locker.beneficiary(), address(0));
        assertEq(locker.beneficiaryShare(), 0);
        assertFalse(locker.root());
        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), block.timestamp + lockDuration);
        assertFalse(locker.staked());
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), address(locker));
    }
}
