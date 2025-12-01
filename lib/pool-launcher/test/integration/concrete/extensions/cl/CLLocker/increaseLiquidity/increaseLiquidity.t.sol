// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract IncreaseLiquidityIntegrationConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

    uint256 public liquidityToMint;
    uint256 public reserveRatio;
    uint256 public leftover;

    IERC20 public rewardToken;
    address public notifyAdmin;
    uint256 public rewardAmount;

    function setUp() public virtual override {
        BaseForkFixture.setUp();

        poolLauncherToken = address(token);
        tokenToPair = address(usdc);

        reserveRatio = 1e12;
        leftover = 999999;
        uint256 tokensToMint = 1000;
        liquidityToMint = reserveRatio * tokensToMint - 1;
        amountToken0 = address(token) < address(usdc) ? tokensToMint * TOKEN_1 : tokensToMint * USDC_1;
        amountToken1 = address(token) < address(usdc) ? tokensToMint * USDC_1 : tokensToMint * TOKEN_1;
        notifyAdmin = 0xE6A41fE61E7a1996B59d508661e3f524d6A32075;
        rewardToken = IERC20(IVotingEscrow(IVoter(voter).ve()).token());
        rewardAmount = 100 * TOKEN_1;

        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        vm.startPrank(users.alice);
        usdc.approve(address(clPoolLauncher), usdcAmount);
        token.approve(address(clPoolLauncher), poolLauncherAmount);
        vm.stopPrank();

        uint160 sqrtPrice = encodePriceSqrt({reserve1: 1, reserve0: reserveRatio});
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

        /// @dev Reset Alice's balances
        deal(address(usdc), users.alice, 0);
        deal(address(token), users.alice, 0);

        clPool = poolLauncherPool.pool;
        locker = ICLLocker(_locker);
        lp = IERC721(nfpManager).tokenOfOwnerByIndex(_locker, 0);

        vm.prank(IVoter(voter).governor());
        gauge = IVoter(voter).createGauge({poolFactory: clFactory, pool: clPool});
    }

    function _stakeAndNotifyGauge() internal {
        locker.stake();

        deal(address(rewardToken), notifyAdmin, rewardAmount);
        vm.startPrank(notifyAdmin);
        rewardToken.approve(gauge, rewardAmount);
        IGauge(gauge).notifyRewardWithoutClaim({amount: rewardAmount});
        skip(7 days);
        vm.stopPrank();

        vm.startPrank(users.alice);
    }

    function test_WhenTheCallerIsNotTheOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        vm.prank(users.charlie);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.charlie));
        locker.increaseLiquidity({_amount0: amountToken0, _amount1: amountToken1, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerIsNotLocked() external whenTheCallerIsTheOwner {
        // It should revert with {NotLocked}
        skip(lockDuration);
        clLockerFactory.unlock({_locker: address(locker), _recipient: users.alice});
        vm.expectRevert(ILocker.NotLocked.selector);
        locker.increaseLiquidity({_amount0: amountToken0, _amount1: amountToken1, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenTheLockerIsLocked() {
        _;
    }

    function test_WhenBothAmountsAreZero() external whenTheCallerIsTheOwner whenTheLockerIsLocked {
        // It should revert with {ZeroAmount}
        vm.expectRevert(ILocker.ZeroAmount.selector);
        locker.increaseLiquidity({_amount0: 0, _amount1: 0, _amount0Min: 0, _amount1Min: 0});
    }

    modifier whenOneOfTheAmountsIsNotZero() {
        _;
    }

    function test_WhenTheAmountsDepositedAreSmallerThanTheMinimumAmounts()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
    {
        // It should revert with {PSC}
        deal(poolLauncherToken, address(locker), amountToken0);
        deal(tokenToPair, address(locker), amountToken1);

        vm.expectRevert(bytes("PSC"));
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0 + 1,
            _amount1Min: amountToken1
        });
    }

    modifier whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts() {
        _;
    }

    modifier whenTheLockerBalanceIsSmallerThanTheAmounts() {
        _;
    }

    modifier whenTheLockerIsNotStaked() {
        _;
    }

    function test_WhenTheLockerBalanceIsSmallerThanTheSuppliedAmount()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsSmallerThanTheAmounts
        whenTheLockerIsNotStaked
    {
        // It should mint new liquidity for the locker
        // It should increase the lp amount
        // It should refund all leftover tokens to the locker owner
        // It should clear outstanding allowances
        // It should emit a {LiquidityIncreased} event
        uint256 lpBefore = locker.lp();
        uint128 liquidityBefore;
        (,,,,,,, liquidityBefore,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});

        address pool = locker.pool();
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        vm.expectEmit(address(token0));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: leftover});
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({
            amount0: amountToken0 - leftover,
            amount1: amountToken1,
            liquidity: liquidityToMint
        });
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0 - leftover,
            _amount1Min: amountToken1
        });

        uint128 liquidityAfter;
        (,,,,,,, liquidityAfter,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(locker.lp(), lpBefore);
        assertEq(liquidityAfter, liquidityBefore + liquidityToMint);

        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0 - leftover);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to alice, no outstanding balances in locker
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), leftover);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), 0);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), nfpManager), 0);
        assertEq(token1.allowance(address(locker), nfpManager), 0);
    }

    function test_WhenTheLockerBalanceIsGreaterThanOrEqualToTheSuppliedAmount()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsSmallerThanTheAmounts
        whenTheLockerIsNotStaked
    {
        // It should mint new liquidity for the locker
        // It should increase the lp amount
        // It should refund the supplied amount to the locker owner
        // It should clear outstanding allowances
        // It should emit a {LiquidityIncreased} event
        uint256 lpBefore = locker.lp();
        uint128 liquidityBefore;
        (,,,,,,, liquidityBefore,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});

        address pool = locker.pool();
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        /// @dev Simulate leftover greater than amount of tokens provided by user, to ensure no refund of locked tokens
        uint256 lockerLeftover = TOKEN_1;
        uint256 lockerBal = amountToken0 + lockerLeftover;

        deal(address(token0), address(locker), lockerBal);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        liquidityToMint = 500000000000027;
        uint256 amount0Increased = 500000000000027000001;
        uint256 amount1Increased = amountToken1 / 2;

        vm.expectEmit(address(token0));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: amountToken0});
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({
            amount0: amount0Increased,
            amount1: amountToken1 / 2,
            liquidity: liquidityToMint
        });
        locker.increaseLiquidity({
            _amount0: amountToken0 + lockerBal,
            _amount1: amountToken1 / 2,
            _amount0Min: (amountToken0 - leftover) / 2,
            _amount1Min: amountToken1 / 2
        });

        uint128 liquidityAfter;
        (,,,,,,, liquidityAfter,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(locker.lp(), lpBefore);
        assertEq(liquidityAfter, liquidityBefore + liquidityToMint);

        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amount0Increased);
        assertEq(balanceToken1After, balanceToken1Before + amount1Increased);

        /// @dev Full token amount is refunded to alice, leftover refunded to locker
        assertEq(token1.balanceOf({account: users.alice}), 5e8);
        assertEq(token0.balanceOf({account: users.alice}), 1000e18);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), 500999999999972999999);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), nfpManager), 0);
        assertEq(token1.allowance(address(locker), nfpManager), 0);
    }

    modifier whenTheLockerIsStaked() {
        _;
    }

    function test_WhenTheLockerBalanceIsSmallerThanTheSuppliedAmount_()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsSmallerThanTheAmounts
        whenTheLockerIsStaked
    {
        // It should mint new liquidity for the locker
        // It should increase the lp amount
        // It should refund all leftover tokens to the locker owner
        // It should deposit the additional liquidity in the gauge
        // It should clear outstanding allowances
        // It should emit a {LiquidityIncreased} event
        _stakeAndNotifyGauge();

        uint256 lpBefore = locker.lp();
        uint128 liquidityBefore;
        (,,,,,,, liquidityBefore,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});

        address pool = locker.pool();
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        assertEq(ICLPool(pool).stakedLiquidity(), liquidityBefore);

        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        vm.expectEmit(address(gauge));
        emit IGauge.ClaimRewards({from: address(locker), amount: rewardAmount - 1});
        vm.expectEmit(address(gauge));
        emit IGauge.Withdraw({user: address(locker), tokenId: locker.lp(), liquidityToStake: liquidityBefore});
        vm.expectEmit(address(token0));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: leftover});
        vm.expectEmit(address(gauge));
        emit IGauge.Deposit({
            user: address(locker),
            tokenId: locker.lp(),
            liquidityToStake: liquidityBefore + uint128(liquidityToMint)
        });
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({
            amount0: amountToken0 - leftover,
            amount1: amountToken1,
            liquidity: liquidityToMint
        });
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0 - leftover,
            _amount1Min: amountToken1
        });

        uint128 liquidityAfter;
        (,,,,,,, liquidityAfter,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(locker.lp(), lpBefore);
        assertEq(liquidityAfter, liquidityBefore + liquidityToMint);
        assertEq(ICLPool(pool).stakedLiquidity(), liquidityBefore + liquidityToMint);

        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0 - leftover);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to alice, no outstanding balances in locker
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), leftover);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), 0);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), nfpManager), 0);
        assertEq(token1.allowance(address(locker), nfpManager), 0);
    }

    function test_WhenTheLockerBalanceIsGreaterThanOrEqualToTheSuppliedAmount_()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsSmallerThanTheAmounts
        whenTheLockerIsStaked
    {
        // It should mint new liquidity for the locker
        // It should increase the lp amount
        // It should refund the supplied amount to the locker owner
        // It should deposit the additional liquidity in the gauge
        // It should clear outstanding allowances
        // It should emit a {LiquidityIncreased} event
        _stakeAndNotifyGauge();

        uint256 lpBefore = locker.lp();
        uint128 liquidityBefore;
        (,,,,,,, liquidityBefore,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});

        address pool = locker.pool();
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        assertEq(ICLPool(pool).stakedLiquidity(), liquidityBefore);

        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        /// @dev Simulate leftover greater than amount of tokens provided by user, to ensure no refund of locked tokens
        uint256 lockerLeftover = TOKEN_1;
        uint256 lockerBal = amountToken0 + lockerLeftover;

        deal(address(token0), address(locker), lockerBal);
        deal(address(token1), address(locker), amountToken1);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        liquidityToMint = 500000000000027;
        uint256 amount0Increased = 500000000000027000001;
        uint256 amount1Increased = amountToken1 / 2;

        vm.expectEmit(address(gauge));
        emit IGauge.ClaimRewards({from: address(locker), amount: rewardAmount - 1});
        vm.expectEmit(address(gauge));
        emit IGauge.Withdraw({user: address(locker), tokenId: locker.lp(), liquidityToStake: liquidityBefore});
        vm.expectEmit(address(token0));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: amountToken0});
        vm.expectEmit(address(gauge));
        emit IGauge.Deposit({
            user: address(locker),
            tokenId: locker.lp(),
            liquidityToStake: liquidityBefore + uint128(liquidityToMint)
        });
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({
            amount0: amount0Increased,
            amount1: amountToken1 / 2,
            liquidity: liquidityToMint
        });
        locker.increaseLiquidity({
            _amount0: amountToken0 + lockerBal,
            _amount1: amountToken1 / 2,
            _amount0Min: (amountToken0 - leftover) / 2,
            _amount1Min: amountToken1 / 2
        });

        uint128 liquidityAfter;
        (,,,,,,, liquidityAfter,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(locker.lp(), lpBefore);
        assertEq(liquidityAfter, liquidityBefore + liquidityToMint);
        assertEq(ICLPool(pool).stakedLiquidity(), liquidityBefore + liquidityToMint);

        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amount0Increased);
        assertEq(balanceToken1After, balanceToken1Before + amount1Increased);

        /// @dev Full token amount is refunded to alice, leftover refunded to locker
        assertEq(token1.balanceOf({account: users.alice}), 1e9);
        assertEq(token0.balanceOf({account: users.alice}), amountToken0);
        assertEq(token1.balanceOf({account: address(locker)}), amountToken1 / 2);
        assertEq(token0.balanceOf({account: address(locker)}), 500999999999972999999);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), nfpManager), 0);
        assertEq(token1.allowance(address(locker), nfpManager), 0);
    }

    modifier whenTheLockerBalanceIsNotSmallerThanTheAmounts() {
        _;
    }

    function test_WhenTheLockerIsNotStaked_()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsNotSmallerThanTheAmounts
    {
        // It should mint new liquidity for the locker
        // It should increase the lp amount
        // It should refund leftover tokens back to the locker
        // It should clear outstanding allowances
        // It should emit a {LiquidityIncreased} event
        uint256 lpBefore = locker.lp();
        uint128 liquidityBefore;
        (,,,,,,, liquidityBefore,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});

        address pool = locker.pool();
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        deal(address(token0), address(locker), amountToken0);
        deal(address(token1), address(locker), amountToken1);

        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({
            amount0: amountToken0 - leftover,
            amount1: amountToken1,
            liquidity: liquidityToMint
        });
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0 - leftover,
            _amount1Min: amountToken1
        });

        uint128 liquidityAfter;
        (,,,,,,, liquidityAfter,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(locker.lp(), lpBefore);
        assertEq(liquidityAfter, liquidityBefore + liquidityToMint);

        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0 - leftover);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to locker, no outstanding balances for alice
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), 0);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), leftover);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), nfpManager), 0);
        assertEq(token1.allowance(address(locker), nfpManager), 0);
    }

    function test_WhenTheLockerIsStaked_()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsNotSmallerThanTheAmounts
    {
        // It should mint new liquidity for the locker
        // It should increase the lp amount
        // It should refund leftover tokens back to the locker
        // It should deposit the additional liquidity in the gauge
        // It should clear outstanding allowances
        // It should emit a {LiquidityIncreased} event
        _stakeAndNotifyGauge();

        uint256 lpBefore = locker.lp();
        uint128 liquidityBefore;
        (,,,,,,, liquidityBefore,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});

        address pool = locker.pool();
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        deal(address(token0), address(locker), amountToken0);
        deal(address(token1), address(locker), amountToken1);

        vm.expectEmit(address(gauge));
        emit IGauge.ClaimRewards({from: address(locker), amount: rewardAmount - 1});
        vm.expectEmit(address(gauge));
        emit IGauge.Withdraw({user: address(locker), tokenId: locker.lp(), liquidityToStake: liquidityBefore});
        vm.expectEmit(address(gauge));
        emit IGauge.Deposit({
            user: address(locker),
            tokenId: locker.lp(),
            liquidityToStake: liquidityBefore + uint128(liquidityToMint)
        });
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({
            amount0: amountToken0 - leftover,
            amount1: amountToken1,
            liquidity: liquidityToMint
        });
        locker.increaseLiquidity({_amount0: amountToken0, _amount1: amountToken1, _amount0Min: 0, _amount1Min: 0});

        uint128 liquidityAfter;
        (,,,,,,, liquidityAfter,,,,) = INfpm(nfpManager).positions({tokenId: locker.lp()});
        assertEq(locker.lp(), lpBefore);
        assertEq(liquidityAfter, liquidityBefore + liquidityToMint);

        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0 - leftover);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to locker, no outstanding balances for alice
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), 0);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), leftover);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), nfpManager), 0);
        assertEq(token1.allowance(address(locker), nfpManager), 0);
    }

    function testGas_increaseLiquidity()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsSmallerThanTheAmounts
        whenTheLockerIsStaked
    {
        _stakeAndNotifyGauge();

        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        /// @dev Simulate leftover greater than amount of tokens provided by user, to ensure no refund of locked tokens
        uint256 lockerLeftover = TOKEN_1;
        uint256 lockerBal = amountToken0 + lockerLeftover;

        deal(address(token0), address(locker), lockerBal);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0 - leftover,
            _amount1Min: amountToken1
        });
        vm.snapshotGasLastCall("CLLocker_increaseLiquidity");
    }
}
