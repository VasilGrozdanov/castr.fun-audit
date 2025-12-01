// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2LockerFactory.t.sol";

contract UnlockIntegrationConcreteTest is V2LockerFactoryTest {
    using stdStorage for StdStorage;

    address public _locker;
    address public _recipient;
    uint256 _fees0;
    uint256 _fees1;
    IERC20 token0;
    IERC20 token1;

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));
        (_fees0, _fees1) = poolLauncherToken < tokenToPair ? (10 * TOKEN_1, 10 * USDC_1) : (10 * USDC_1, 10 * TOKEN_1);

        //mock fees by sending tokens to the pool fees and updating claimable in storage
        address pool = v2Pool;
        address poolFees = IV2Pool(pool).poolFees();

        deal(address(token0), poolFees, _fees0);
        deal(address(token1), poolFees, _fees1);

        stdstore.target({_target: pool}).sig("claimable0(address)").with_key(address(locker)).checked_write(_fees0);
        stdstore.target({_target: pool}).sig("claimable1(address)").with_key(address(locker)).checked_write(_fees1);
    }

    function test_WhenTheRecipientIsTheZeroAddress() external {
        // It should revert with {ZeroAddress}
        _locker = makeAddr("locker");
        _recipient = address(0);

        vm.expectRevert(ILockerFactory.ZeroAddress.selector);
        v2LockerFactory.unlock({_locker: _locker, _recipient: _recipient});
    }

    modifier whenTheRecipientIsNotTheZeroAddress() {
        _recipient = users.alice;
        _;
    }

    function test_WhenTheLockerDoesNotExist() external whenTheRecipientIsNotTheZeroAddress {
        // It should revert with {NotLocker}
        _locker = makeAddr("locker");

        vm.expectRevert(ILockerFactory.NotLocker.selector);
        v2LockerFactory.unlock({_locker: _locker, _recipient: _recipient});
    }

    modifier whenTheLockerExists() {
        _locker = address(locker);
        _;
    }

    function test_WhenTheCallerIsNotTheLockerOwner() external whenTheRecipientIsNotTheZeroAddress whenTheLockerExists {
        // It should revert with {NotLockerOwner}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(ILockerFactory.NotLockerOwner.selector);
        v2LockerFactory.unlock({_locker: _locker, _recipient: _recipient});
    }

    modifier whenTheCallerIsTheLockerOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerHasNotExpired()
        external
        whenTheRecipientIsNotTheZeroAddress
        whenTheLockerExists
        whenTheCallerIsTheLockerOwner
    {
        // It should revert with {Locked}
        vm.expectRevert(ILockerFactory.Locked.selector);
        v2LockerFactory.unlock({_locker: _locker, _recipient: _recipient});
    }

    modifier whenTheLockerHasExpired() {
        vm.warp(locker.lockedUntil());
        _;
    }

    function test_WhenTheLockerIsStaked()
        external
        whenTheRecipientIsNotTheZeroAddress
        whenTheLockerExists
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasExpired
    {
        // It should revert with {Staked}
        locker.stake();
        vm.expectRevert(ILockerFactory.Staked.selector);
        v2LockerFactory.unlock({_locker: _locker, _recipient: _recipient});
    }

    function test_WhenTheLockerIsNotStaked()
        external
        whenTheRecipientIsNotTheZeroAddress
        whenTheLockerExists
        whenTheCallerIsTheLockerOwner
        whenTheLockerHasExpired
    {
        // It should claim the available fees
        // It should remove the locker from the instances mapping
        // It should remove the locker from the pool's set of lockers
        // It should unlock the locker
        // It should transfer the liquidity to the recipient
        // It should emit a {LockerUnlocked} event
        uint256 balance0Before = token0.balanceOf(users.alice);
        uint256 balance1Before = token1.balanceOf(users.alice);
        vm.expectCall(_locker, abi.encodeCall(ILocker.unlock, (_recipient, _recipient)));
        vm.expectEmit({emitter: address(v2LockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: _locker,
            underlyingPool: v2Pool,
            recipient: _recipient,
            refundAddress: _recipient
        });
        v2LockerFactory.unlock({_locker: _locker, _recipient: _recipient});

        assertFalse(v2LockerFactory.instances(_locker));
        assertEq(IV2Pool(v2Pool).balanceOf(address(locker)), 0);
        assertEq(IV2Pool(v2Pool).balanceOf(users.alice), locker.lp());

        assertEq(token0.balanceOf(users.alice) - balance0Before, _fees0);
        assertEq(token1.balanceOf(users.alice) - balance1Before, _fees1);

        _assertMappings(0, address(0), address(0));
    }
}
