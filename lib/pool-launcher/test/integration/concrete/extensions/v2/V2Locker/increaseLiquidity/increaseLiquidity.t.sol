// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract IncreaseLiquidityIntegrationConcreteTest is V2LockerTest {
    using stdStorage for StdStorage;

    function test_WhenTheCallerIsNotTheOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.charlie));
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerIsNotLocked() external whenTheCallerIsTheOwner {
        // It should revert with {NotLocked}
        skip(lockDuration);
        v2LockerFactory.unlock({_locker: address(locker), _recipient: users.alice});
        vm.expectRevert(ILocker.NotLocked.selector);
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });
    }

    modifier whenTheLockerIsLocked() {
        _;
    }

    function test_WhenBothAmountsAreZero() external whenTheCallerIsTheOwner whenTheLockerIsLocked {
        // It should revert with {ZeroAmount}
        vm.expectRevert(ILocker.ZeroAmount.selector);
        locker.increaseLiquidity({_amount0: 0, _amount1: 0, _amount0Min: amountToken0, _amount1Min: amountToken1});
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
        // It should revert with {InsufficientAmount}
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        /// @dev Increase amount0 desired to simulate leftovers
        uint256 leftover = amountToken0 / 1000;
        uint256 amountToken0Desired = amountToken0 + leftover;

        deal(address(token0), address(locker), amountToken0Desired);
        deal(address(token1), address(locker), amountToken1);

        vm.expectRevert(IV2Router.InsufficientAmountA.selector);
        locker.increaseLiquidity({
            _amount0: amountToken0Desired,
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
        address pool = address(locker.pool());
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        /// @dev Increase amount1 desired to simulate leftovers
        uint256 leftover = amountToken1 / 1000;
        uint256 amountToken1Desired = amountToken1 + leftover;

        deal(address(token1), address(locker), leftover);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        vm.expectEmit(address(token1));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: leftover});
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({amount0: amountToken0, amount1: amountToken1, liquidity: 1e18});
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1Desired,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });

        assertEq(locker.lp(), lpBefore + 1e18);
        assertEq(IV2Pool(pool).balanceOf({account: address(locker)}), locker.lp());
        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to alice, no outstanding balances in locker
        assertEq(token1.balanceOf({account: users.alice}), leftover);
        assertEq(token0.balanceOf({account: users.alice}), 0);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), 0);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), v2Router), 0);
        assertEq(token1.allowance(address(locker), v2Router), 0);
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
        address pool = address(locker.pool());
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

        vm.expectEmit(address(token0));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: amountToken0});
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({amount0: amountToken0, amount1: amountToken1, liquidity: 1e18});
        locker.increaseLiquidity({
            _amount0: lockerBal + amountToken0,
            _amount1: amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });

        assertEq(locker.lp(), lpBefore + 1e18);
        assertEq(IV2Pool(pool).balanceOf({account: address(locker)}), locker.lp());
        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Full token amount is refunded to alice, leftover refunded to locker
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), amountToken0);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), lockerLeftover);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), v2Router), 0);
        assertEq(token1.allowance(address(locker), v2Router), 0);
    }

    modifier whenTheLockerIsStaked() {
        locker.stake();
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
        uint256 lpBefore = locker.lp();
        address gauge = address(locker.gauge());
        address pool = address(locker.pool());
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});
        assertEq(IV2Pool(locker.pool()).balanceOf({account: gauge}), lpBefore);

        /// @dev Increase amount0 desired to simulate leftovers
        uint256 leftover = amountToken0 / 1000;
        uint256 amountToken0Desired = amountToken0 + leftover;

        deal(address(token0), address(locker), leftover);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        vm.expectEmit(address(token0));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: leftover});
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({amount0: amountToken0, amount1: amountToken1, liquidity: 1e18});
        locker.increaseLiquidity({
            _amount0: amountToken0Desired,
            _amount1: amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });

        assertEq(locker.lp(), lpBefore + 1e18);
        assertEq(IV2Pool(pool).balanceOf({account: gauge}), locker.lp());
        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to alice, no outstanding balances in locker
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), leftover);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), 0);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), v2Router), 0);
        assertEq(token1.allowance(address(locker), v2Router), 0);
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
        uint256 lpBefore = locker.lp();
        address pool = address(locker.pool());
        address gauge = address(locker.gauge());
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});
        assertEq(IV2Pool(locker.pool()).balanceOf({account: gauge}), lpBefore);

        /// @dev Simulate leftover greater than amount of tokens provided by user, to ensure no refund of locked tokens
        uint256 lockerLeftover = TOKEN_1;
        uint256 lockerBal = amountToken1 + lockerLeftover;

        deal(address(token1), address(locker), lockerBal);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        vm.expectEmit(address(token1));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: amountToken1});
        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({amount0: amountToken0, amount1: amountToken1, liquidity: 1e18});
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: lockerBal + amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });

        assertEq(locker.lp(), lpBefore + 1e18);
        assertEq(IV2Pool(pool).balanceOf({account: gauge}), locker.lp());
        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Full token amount is refunded to alice, leftover refunded to locker
        assertEq(token1.balanceOf({account: users.alice}), amountToken1);
        assertEq(token0.balanceOf({account: users.alice}), 0);
        assertEq(token1.balanceOf({account: address(locker)}), lockerLeftover);
        assertEq(token0.balanceOf({account: address(locker)}), 0);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), v2Router), 0);
        assertEq(token1.allowance(address(locker), v2Router), 0);
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
        address pool = address(locker.pool());
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});

        /// @dev Increase amount0 desired to simulate leftovers
        uint256 leftover = amountToken0 / 1000;
        uint256 amountToken0Desired = amountToken0 + leftover;

        deal(address(token0), address(locker), amountToken0Desired);
        deal(address(token1), address(locker), amountToken1);

        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({amount0: amountToken0, amount1: amountToken1, liquidity: 1e18});
        locker.increaseLiquidity({
            _amount0: amountToken0Desired,
            _amount1: amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });

        assertEq(locker.lp(), lpBefore + 1e18);
        assertEq(IV2Pool(pool).balanceOf({account: address(locker)}), locker.lp());
        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to locker, no outstanding balances for alice
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), 0);
        assertEq(token1.balanceOf({account: address(locker)}), 0);
        assertEq(token0.balanceOf({account: address(locker)}), leftover);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), v2Router), 0);
        assertEq(token1.allowance(address(locker), v2Router), 0);
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
        locker.stake();

        uint256 lpBefore = locker.lp();
        address gauge = address(locker.gauge());
        address pool = address(locker.pool());
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());
        uint256 balanceToken0Before = token0.balanceOf({account: pool});
        uint256 balanceToken1Before = token1.balanceOf({account: pool});
        assertEq(IV2Pool(locker.pool()).balanceOf({account: gauge}), lpBefore);

        /// @dev Increase amount1 desired to simulate leftovers
        uint256 leftover = amountToken1 / 1000;
        uint256 amountToken1Desired = amountToken1 + leftover;

        deal(address(token0), address(locker), amountToken0);
        deal(address(token1), address(locker), amountToken1Desired);

        vm.expectEmit(address(locker));
        emit ILocker.LiquidityIncreased({amount0: amountToken0, amount1: amountToken1, liquidity: 1e18});
        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: amountToken1Desired,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });

        assertEq(locker.lp(), lpBefore + 1e18);
        assertEq(IV2Pool(pool).balanceOf({account: gauge}), locker.lp());
        uint256 balanceToken0After = token0.balanceOf({account: pool});
        uint256 balanceToken1After = token1.balanceOf({account: pool});
        assertEq(balanceToken0After, balanceToken0Before + amountToken0);
        assertEq(balanceToken1After, balanceToken1Before + amountToken1);

        /// @dev Leftover is refunded to alice, no outstanding balances in locker
        assertEq(token1.balanceOf({account: users.alice}), 0);
        assertEq(token0.balanceOf({account: users.alice}), 0);
        assertEq(token1.balanceOf({account: address(locker)}), leftover);
        assertEq(token0.balanceOf({account: address(locker)}), 0);

        /// @dev Allowances are cleared
        assertEq(token0.allowance(address(locker), v2Router), 0);
        assertEq(token1.allowance(address(locker), v2Router), 0);
    }

    function testGas_IncreaseLiquidity()
        external
        whenTheCallerIsTheOwner
        whenTheLockerIsLocked
        whenOneOfTheAmountsIsNotZero
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinimumAmounts
        whenTheLockerBalanceIsSmallerThanTheAmounts
        whenTheLockerIsStaked
    {
        IERC20 token0 = IERC20(locker.token0());
        IERC20 token1 = IERC20(locker.token1());

        /// @dev Simulate leftover greater than amount of tokens provided by user, to ensure no refund of locked tokens
        uint256 lockerLeftover = TOKEN_1;
        uint256 lockerBal = amountToken1 + lockerLeftover;

        deal(address(token1), address(locker), lockerBal);

        deal(address(token0), users.alice, amountToken0);
        deal(address(token1), users.alice, amountToken1);
        token0.approve(address(locker), amountToken0);
        token1.approve(address(locker), amountToken1);

        locker.increaseLiquidity({
            _amount0: amountToken0,
            _amount1: lockerBal + amountToken1,
            _amount0Min: amountToken0,
            _amount1Min: amountToken1
        });
        vm.snapshotGasLastCall("V2Locker_increaseLiquidity");
    }
}
