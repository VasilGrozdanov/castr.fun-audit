// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2PoolLauncher.t.sol";

contract LaunchUnitConcreteTest is V2PoolLauncherTest {
    function test_WhenThePoolLauncherTokenIsWhitelisted() external {
        // It should revert with {InvalidPoolLauncherToken}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        vm.prank(users.owner);
        v2PoolLauncher.addPairableToken({_token: _poolLauncherToken});

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });

        vm.prank(users.alice);
        vm.expectRevert(IPoolLauncher.InvalidPoolLauncherToken.selector);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
    }

    modifier whenThePoolLauncherTokenIsNotWhitelisted() {
        _;
    }

    function test_WhenThePoolHasAlreadyBeenCreated() external whenThePoolLauncherTokenIsNotWhitelisted {
        // It should revert with {PoolAlreadyExists}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();

        vm.startPrank(users.charlie);
        vm.expectRevert(IPoolLauncher.PoolAlreadyExists.selector);
        v2PoolLauncher.launch({_params: params, _recipient: users.charlie, _refundAddress: users.charlie});
    }

    modifier whenThePoolHasNotBeenCreatedYet() {
        _;
    }

    function test_WhenTheTokenToPairIsNotWhitelisted()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
    {
        // It should revert with {InvalidToken}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(new BasicERC20("InvalidToken", "InvalidToken", 0));

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });

        vm.startPrank(users.charlie);
        vm.expectRevert(IPoolLauncher.InvalidToken.selector);
        v2PoolLauncher.launch({_params: params, _recipient: users.charlie, _refundAddress: users.charlie});
    }

    modifier whenTheTokenToPairIsWhitelisted() {
        _;
    }

    function test_WhenTheRefundAddressIsTheZeroAddress()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
    {
        // It should revert with {InvalidRefundAddress}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });

        vm.startPrank(users.charlie);
        vm.expectRevert(IPoolLauncher.InvalidRefundAddress.selector);
        v2PoolLauncher.launch({_params: params, _recipient: users.charlie, _refundAddress: address(0)});
    }

    modifier whenTheRefundAddressIsNotTheZeroAddress() {
        _;
    }

    function test_WhenTheBalanceOfPoolLauncherTokenOfTheSenderIsLowerThanAmountPoolLauncherToken()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
    {
        // It should revert with {ERC20InsufficientBalance}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken - 1);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                users.alice,
                _amountPoolLauncherToken - 1,
                _amountPoolLauncherToken
            )
        );

        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();
    }

    modifier whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken() {
        _;
    }

    function test_WhenTheBalanceOfTokenToPairOfTheSenderIsLowerThanAmountTokenToPair()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
    {
        // It should revert with {ERC20InsufficientBalance}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair - 1);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
    }

    modifier whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair() {
        _;
    }

    function test_WhenTheAmountsDepositedAreSmallerThanTheMinAmounts()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
    {
        // It should revert with {InsufficientAmount}
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        uint32 _lockDuration = 86400;

        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair * 2);
        /// @dev Create unbalanced pool to simulate launch leftovers
        vm.startPrank(users.alice);
        address poolAddr =
            IV2Factory(v2Factory).createPool({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: false});
        token.transfer({to: poolAddr, value: _amountPoolLauncherToken});
        usdc.transfer({to: poolAddr, value: _amountTokenToPair * 2});
        IV2Pool(poolAddr).mint({to: users.bob});

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            /// @dev Simulate slippage revert by setting amountMin too high
            amountPoolLauncherTokenMin: _amountPoolLauncherToken / 2 + 1,
            amountTokenToPairMin: _amountTokenToPair,
            lockDuration: _lockDuration
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);

        vm.expectRevert(IV2Router.InsufficientAmountA.selector);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
    }

    modifier whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts() {
        _;
    }

    function test_WhenLockDurationIsZero()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new poolLauncher pool
        // It should return any seed liquidity to the recipient
        // It should refund any leftover tokens to the user
        // It should map the poolLauncher token to the new pool
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: _amountPoolLauncherToken,
            amountTokenToPairMin: _amountTokenToPair,
            lockDuration: 0
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: false});
        vm.expectEmit({emitter: address(v2PoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: _poolLauncherToken,
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: _poolLauncherToken,
                tokenToPair: _tokenToPair
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        assertNotEq(pool.pool, address(0));
        assertEq(pool.pool, predictedUnderlyingPool);
        assertEq(pool.createdAt, block.timestamp);
        assertEq(lockerAddress, address(0));
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: false})
        );
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: false})
        );

        assertEq(IERC20(pool.pool).balanceOf(users.alice), 999999999999000);

        IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);

        /// @dev Ensure no outstanding balances in locker. Balance is used to launch or refunded back to user
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);
        assertEq(token.balanceOf(pool.pool), _amountPoolLauncherToken - token.balanceOf(users.alice));
        assertEq(usdc.balanceOf(pool.pool), _amountTokenToPair - usdc.balanceOf(users.alice));
        assertEq(token.balanceOf(users.alice), _amountPoolLauncherToken - token.balanceOf(pool.pool));
        assertEq(usdc.balanceOf(users.alice), _amountTokenToPair - usdc.balanceOf(pool.pool));
        assertGt(usdc.balanceOf(pool.pool), 0);
        assertGt(token.balanceOf(pool.pool), 0);
    }

    function test_WhenLockDurationIsNotZeroOrUINT32_MAX()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new poolLauncher pool
        // It should lock the seed liquidity in a new Locker for the given duration
        // It should refund any leftover tokens to the user
        // It should map the poolLauncher token to the new pool
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        uint32 _lockDuration = 86400;
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: _amountPoolLauncherToken,
            amountTokenToPairMin: _amountTokenToPair,
            lockDuration: _lockDuration
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: false});
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        vm.expectEmit({emitter: address(v2PoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: _poolLauncherToken,
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: _poolLauncherToken,
                tokenToPair: _tokenToPair
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        assertNotEq(pool.pool, address(0));
        assertEq(pool.pool, predictedUnderlyingPool);
        assertEq(pool.createdAt, block.timestamp);
        assertEq(lockerAddress, predictedLocker);
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: false})
        );
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: false})
        );

        uint256 lp = sqrt(_amountPoolLauncherToken * _amountTokenToPair) - MINIMUM_LIQUIDITY;
        assertEq(IERC20(pool.pool).balanceOf(lockerAddress), lp);
        assertEq(ILocker(lockerAddress).pool(), pool.pool);
        assertEq(ILocker(lockerAddress).lp(), lp);
        assertEq(ILocker(lockerAddress).token0(), _poolLauncherToken);
        assertEq(ILocker(lockerAddress).token1(), _tokenToPair);
        assertEq(ILocker(lockerAddress).lockedUntil(), block.timestamp + _lockDuration);
        assertEq(uint8(ILocker(lockerAddress).poolType()), uint8(ILockerFactory.PoolType.BASIC));

        IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);

        /// @dev Ensure no outstanding balances in locker. Balance is used to launch or refunded back to user
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);
        assertEq(token.balanceOf(pool.pool), _amountPoolLauncherToken - token.balanceOf(users.alice));
        assertEq(usdc.balanceOf(pool.pool), _amountTokenToPair - usdc.balanceOf(users.alice));
        assertEq(token.balanceOf(users.alice), _amountPoolLauncherToken - token.balanceOf(pool.pool));
        assertEq(usdc.balanceOf(users.alice), _amountTokenToPair - usdc.balanceOf(pool.pool));
        assertGt(usdc.balanceOf(pool.pool), 0);
        assertGt(token.balanceOf(pool.pool), 0);
    }

    function test_WhenLockDurationIsNotZeroOrUINT32_MAX_RefundFlow()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new poolLauncher pool
        // It should lock the seed liquidity in a new Locker for the given duration
        // It should refund any leftover tokens to the user
        // It should map the poolLauncher token to the new pool
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        uint32 _lockDuration = 86400;

        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair * 2);
        /// @dev Create unbalanced pool to simulate launch leftovers
        vm.startPrank(users.alice);
        address poolAddr =
            IV2Factory(v2Factory).createPool({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: false});
        token.transfer({to: poolAddr, value: _amountPoolLauncherToken});
        usdc.transfer({to: poolAddr, value: _amountTokenToPair * 2});
        IV2Pool(poolAddr).mint({to: users.bob});

        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: _amountPoolLauncherToken / 2,
            amountTokenToPairMin: _amountTokenToPair,
            lockDuration: _lockDuration
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);

        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        vm.expectEmit({emitter: address(v2PoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: _poolLauncherToken,
            pool: poolAddr,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: poolAddr,
                poolLauncherToken: _poolLauncherToken,
                tokenToPair: _tokenToPair
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        assertNotEq(pool.pool, address(0));
        assertEq(pool.pool, poolAddr);
        assertEq(pool.createdAt, block.timestamp);
        assertEq(lockerAddress, predictedLocker);
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: false})
        );
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: false})
        );

        /// @dev Ensure leftover is sent to alice
        assertEq(token.balanceOf(users.alice), _amountPoolLauncherToken / 2);
        assertEq(usdc.balanceOf(users.alice), 0);
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);

        {
            uint256 depositAmount = _amountPoolLauncherToken - token.balanceOf(users.alice);
            uint256 lp = sqrt(depositAmount * _amountTokenToPair) - MINIMUM_LIQUIDITY;
            assertApproxEqAbs(IERC20(pool.pool).balanceOf(lockerAddress), lp, 1e3);
            assertEq(ILocker(lockerAddress).pool(), pool.pool);
            assertApproxEqAbs(ILocker(lockerAddress).lp(), lp, 1e3);
            assertEq(ILocker(lockerAddress).token0(), _poolLauncherToken);
            assertEq(ILocker(lockerAddress).token1(), _tokenToPair);
            assertEq(ILocker(lockerAddress).lockedUntil(), block.timestamp + _lockDuration);
            assertEq(uint8(ILocker(lockerAddress).poolType()), uint8(ILockerFactory.PoolType.BASIC));

            assertEq(token.balanceOf(lockerAddress), 0);
            assertEq(usdc.balanceOf(lockerAddress), 0);
            /// @dev alice's position (amountPoolLauncherToken /2) and bob's position (amountPoolLauncherToken)
            assertEq(token.balanceOf(pool.pool), _amountPoolLauncherToken + (_amountPoolLauncherToken / 2));
            /// @dev alice's position (amountTokenToPair) and bob's position (amountTokenToPair *2)
            assertEq(usdc.balanceOf(pool.pool), _amountTokenToPair * 3);
        }

        IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool = v2PoolLauncher.pools({_underlyingPool: poolAddr});
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newPoolLauncherPool.pool, poolAddr);
    }

    function test_WhenLockDurationIsUINT32_MAX()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        // It should create a new poolLauncher pool
        // It should permanently lock the seed liquidity in a new Locker
        // It should refund any leftover tokens to the user
        // It should map the poolLauncher token to the new pool
        // It should store the info for the new pool in storage
        // It should emit a {Launch} event
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: _amountPoolLauncherToken,
            amountTokenToPairMin: _amountTokenToPair,
            lockDuration: type(uint32).max
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);

        address predictedUnderlyingPool =
            predictV2PoolAddress({tokenA: _poolLauncherToken, tokenB: _tokenToPair, stable: false});
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 1});

        vm.expectEmit({emitter: address(v2PoolLauncher)});
        emit IPoolLauncher.Launch({
            poolLauncherToken: _poolLauncherToken,
            pool: predictedUnderlyingPool,
            sender: users.alice,
            poolLauncherPool: IPoolLauncher.PoolLauncherPool({
                createdAt: uint32(block.timestamp),
                pool: predictedUnderlyingPool,
                poolLauncherToken: _poolLauncherToken,
                tokenToPair: _tokenToPair
            })
        });
        (IPoolLauncher.PoolLauncherPool memory pool, address lockerAddress) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});

        assertNotEq(pool.pool, address(0));
        assertEq(pool.pool, predictedUnderlyingPool);
        assertEq(pool.createdAt, block.timestamp);
        assertEq(lockerAddress, predictedLocker);
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _poolLauncherToken, _tokenB: _tokenToPair, _stable: false})
        );
        assertEq(
            pool.pool, v2PoolLauncher.getPool({_tokenA: _tokenToPair, _tokenB: _poolLauncherToken, _stable: false})
        );

        uint256 lp = sqrt(_amountPoolLauncherToken * _amountTokenToPair) - MINIMUM_LIQUIDITY;
        assertEq(IERC20(pool.pool).balanceOf(lockerAddress), lp);
        assertEq(ILocker(lockerAddress).lp(), lp);
        assertEq(ILocker(lockerAddress).lockedUntil(), type(uint32).max);
        assertEq(ILocker(lockerAddress).pool(), pool.pool);
        assertEq(uint8(ILocker(lockerAddress).poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(ILocker(lockerAddress).token0(), _poolLauncherToken);
        assertEq(ILocker(lockerAddress).token1(), _tokenToPair);

        IPoolLauncher.PoolLauncherPool memory newPoolLauncherPool =
            v2PoolLauncher.pools({_underlyingPool: predictedUnderlyingPool});
        assertEq(newPoolLauncherPool.createdAt, block.timestamp);
        assertEq(newPoolLauncherPool.pool, predictedUnderlyingPool);

        /// @dev Ensure no outstanding balances in locker. Balance is used to launch or refunded back to user
        assertEq(token.balanceOf(lockerAddress), 0);
        assertEq(usdc.balanceOf(lockerAddress), 0);
        assertEq(token.balanceOf(pool.pool), _amountPoolLauncherToken - token.balanceOf(users.alice));
        assertEq(usdc.balanceOf(pool.pool), _amountTokenToPair - usdc.balanceOf(users.alice));
        assertEq(token.balanceOf(users.alice), _amountPoolLauncherToken - token.balanceOf(pool.pool));
        assertEq(usdc.balanceOf(users.alice), _amountTokenToPair - usdc.balanceOf(pool.pool));
        assertGt(usdc.balanceOf(pool.pool), 0);
        assertGt(token.balanceOf(pool.pool), 0);
    }

    function testGas_launch()
        external
        whenThePoolLauncherTokenIsNotWhitelisted
        whenThePoolHasNotBeenCreatedYet
        whenTheTokenToPairIsWhitelisted
        whenTheRefundAddressIsNotTheZeroAddress
        whenTheBalanceOfPoolLauncherTokenOfTheSenderIsHigherOrEqualToAmountPoolLauncherToken
        whenTheBalanceOfTokenToPairOfTheSenderIsHigherOrEqualToAmountTokenToPair
        whenTheAmountsDepositedAreGreaterThanOrEqualToTheMinAmounts
    {
        uint256 _amountPoolLauncherToken = 1000 * TOKEN_1;
        uint256 _amountTokenToPair = 1000 * USDC_1;
        address _poolLauncherToken = address(token);
        address _tokenToPair = address(usdc);
        IV2PoolLauncher.LiquidityParams memory liquidityParams = IV2PoolLauncher.LiquidityParams({
            amountPoolLauncherToken: _amountPoolLauncherToken,
            amountTokenToPair: _amountTokenToPair,
            amountPoolLauncherTokenMin: _amountPoolLauncherToken,
            amountTokenToPairMin: _amountTokenToPair,
            lockDuration: type(uint32).max
        });
        IV2PoolLauncher.LaunchParams memory params = IV2PoolLauncher.LaunchParams({
            poolLauncherToken: _poolLauncherToken,
            tokenToPair: _tokenToPair,
            stable: false,
            liquidity: liquidityParams
        });
        deal(_poolLauncherToken, users.alice, _amountPoolLauncherToken);
        deal(_tokenToPair, users.alice, _amountTokenToPair);

        vm.startPrank(users.alice);
        token.approve(address(v2PoolLauncher), _amountPoolLauncherToken);
        usdc.approve(address(v2PoolLauncher), _amountTokenToPair);
        v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.snapshotGasLastCall("V2PoolLauncher_launch");
    }
}
