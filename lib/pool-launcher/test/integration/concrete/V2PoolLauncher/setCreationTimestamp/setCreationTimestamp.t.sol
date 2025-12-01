// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2PoolLauncher.t.sol";

contract SetCreationTimestampIntegrationConcreteTest is V2PoolLauncherTest {
    address public v2Pool;

    address public _pool;
    uint32 public _creationTimestamp;

    function setUp() public virtual override {
        super.setUp();

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

        (IPoolLauncher.PoolLauncherPool memory poolLauncherPool,) =
            v2PoolLauncher.launch({_params: params, _recipient: users.alice, _refundAddress: users.alice});
        vm.stopPrank();
        v2Pool = poolLauncherPool.pool;
    }

    function test_WhenTheCallerIsNotTheOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    modifier whenTheCallerIsTheOwner() {
        vm.startPrank(users.owner);
        _;
    }

    function test_WhenThePoolIsTheZeroAddress() external whenTheCallerIsTheOwner {
        // It should revert with {ZeroAddress}
        vm.expectRevert(IPoolLauncher.ZeroAddress.selector);
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
    }

    modifier whenThePoolIsNotTheZeroAddress() {
        _pool = makeAddr("pool");
        _;
    }

    function test_WhenTheCreationTimestampIsZero() external whenTheCallerIsTheOwner whenThePoolIsNotTheZeroAddress {
        // It should revert with {ZeroTimestamp}
        _creationTimestamp = 0;

        vm.expectRevert(IPoolLauncher.ZeroTimestamp.selector);
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
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
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
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
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
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
        _pool = v2Pool;

        vm.expectEmit(address(v2PoolLauncher));
        emit IPoolLauncher.CreationTimestampSet({pool: v2Pool, createdAt: _creationTimestamp});
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});

        assertEq(v2PoolLauncher.pools({_underlyingPool: v2Pool}).createdAt, _creationTimestamp);
    }

    function testGas_WhenThePoolIsRegisteredInPoolLauncher()
        external
        whenTheCallerIsTheOwner
        whenThePoolIsNotTheZeroAddress
        whenTheCreationTimestampIsNotZero
        whenTheCreationTimestampIsSmallerThanTheBlockTimestamp
    {
        _pool = v2Pool;
        v2PoolLauncher.setCreationTimestamp({_pool: _pool, _createdAt: _creationTimestamp});
        vm.snapshotGasLastCall("V2PoolLauncher_setCreationTimestamp");
    }
}
