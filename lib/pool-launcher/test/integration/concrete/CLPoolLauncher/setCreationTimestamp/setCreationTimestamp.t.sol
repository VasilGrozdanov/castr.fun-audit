// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLPoolLauncher.t.sol";

contract SetCreationTimestampIntegrationConcreteTest is CLPoolLauncherTest {
    address public clPool;

    address public _pool;
    uint32 public _creationTimestamp;

    function setUp() public virtual override {
        super.setUp();

        uint256 poolLauncherAmount = TOKEN_1 * 1_000_000;
        uint256 usdcAmount = USDC_1 * 1_000_000;
        deal(address(usdc), users.alice, usdcAmount);
        deal(address(token), users.alice, poolLauncherAmount);

        vm.startPrank(users.alice);
        usdc.approve(address(clPoolLauncher), usdcAmount);
        token.approve(address(clPoolLauncher), poolLauncherAmount);
        vm.stopPrank();

        /// @dev USDC is token1, `poolLauncherToken` is token0
        uint160 sqrtPrice = encodePriceSqrt({reserve1: 1e12, reserve0: 1});
        ICLPoolLauncher.LiquidityParams memory liqParams = ICLPoolLauncher.LiquidityParams({
            amountPoolLauncherToken: poolLauncherAmount,
            amountTokenToPair: usdcAmount,
            amountPoolLauncherTokenMin: 0,
            amountTokenToPairMin: 0,
            initialSqrtPriceX96: sqrtPrice,
            tickLower: getMinTick({tickSpacing: TICK_SPACING_200}),
            tickUpper: getMaxTick({tickSpacing: TICK_SPACING_200}),
            lockDuration: 86400
        });

        ICLPoolLauncher.LaunchParams memory launchParams = ICLPoolLauncher.LaunchParams({
            poolLauncherToken: address(token),
            tokenToPair: address(usdc),
            tickSpacing: TICK_SPACING_200,
            liquidity: liqParams
        });

        vm.prank(users.alice);
        (IPoolLauncher.PoolLauncherPool memory poolLauncherPool,) =
            clPoolLauncher.launch({_params: launchParams, _recipient: users.alice});
        clPool = poolLauncherPool.pool;
    }

    function test_WhenTheCallerIsNotTheOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.owner);
        _;
    }

    function test_WhenThePoolIsTheZeroAddress() external whenTheCallerIsTheOwner {
        // It should revert with {ZeroAddress}
        vm.expectRevert(IPoolLauncher.ZeroAddress.selector);
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    modifier whenThePoolIsNotTheZeroAddress() {
        _pool = makeAddr("pool");
        _;
    }

    function test_WhenTheCreationTimestampIsZero() external whenTheCallerIsTheOwner whenThePoolIsNotTheZeroAddress {
        // It should revert with {ZeroTimestamp}
        _creationTimestamp = 0;

        vm.expectRevert(IPoolLauncher.ZeroTimestamp.selector);
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    modifier whenTheCreationTimestampIsNotZero() {
        _;
    }

    function test_WhenTheCreationTimestampIsEqualOrGreaterThanTheBlockTimestamp()
        external
        whenTheCallerIsTheOwner
        whenThePoolIsNotTheZeroAddress
        whenTheCreationTimestampIsNotZero
    {
        // It should revert with {InvalidTimestamp}
        _creationTimestamp = uint32(block.timestamp);

        vm.expectRevert(IPoolLauncher.InvalidTimestamp.selector);
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    modifier whenTheCreationTimestampIsSmallerThanTheBlockTimestamp() {
        _creationTimestamp = uint32(block.timestamp - 52 weeks);
        _;
    }

    function test_WhenThePoolIsNotRegisteredInPoolLauncher()
        external
        whenTheCallerIsTheOwner
        whenThePoolIsNotTheZeroAddress
        whenTheCreationTimestampIsNotZero
        whenTheCreationTimestampIsSmallerThanTheBlockTimestamp
    {
        // It should revert with {PoolNotInPoolLauncher}
        vm.expectRevert(IPoolLauncher.PoolNotInPoolLauncher.selector);
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    function test_WhenThePoolIsRegisteredInPoolLauncher()
        external
        whenTheCallerIsTheOwner
        whenThePoolIsNotTheZeroAddress
        whenTheCreationTimestampIsNotZero
        whenTheCreationTimestampIsSmallerThanTheBlockTimestamp
    {
        // It should set a new timestamp for the pool
        // It should emit a {CreationTimestampSet} event
        _pool = clPool;

        vm.expectEmit(address(clPoolLauncher));
        emit IPoolLauncher.CreationTimestampSet({pool: clPool, createdAt: _creationTimestamp});
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});

        assertEq(clPoolLauncher.pools({_underlyingPool: clPool}).createdAt, _creationTimestamp);
    }

    function testGas_setCreationTimestamp()
        external
        whenTheCallerIsTheOwner
        whenThePoolIsNotTheZeroAddress
        whenTheCreationTimestampIsNotZero
        whenTheCreationTimestampIsSmallerThanTheBlockTimestamp
    {
        _pool = clPool;
        clPoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
        vm.snapshotGasLastCall("CLPoolLauncher_setCreationTimestamp");
    }
}
