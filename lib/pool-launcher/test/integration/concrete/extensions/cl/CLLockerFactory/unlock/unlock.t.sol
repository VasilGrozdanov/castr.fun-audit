// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLockerFactory.t.sol";

contract UnlockIntegrationConcreteTest is CLLockerFactoryTest {
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

        //mock fees by sending tokens to the pool and updating the position in storage
        deal(address(token0), clPool, _fees0);
        deal(address(token1), clPool, _fees1);

        bytes32 positionKey = computeCLPositionKey(nfpManager, tickLower, tickUpper);

        // Find the base slot for positions[key] in CLclPool
        uint256 baseSlot = stdstore.target(clPool).sig("positions(bytes32)").with_key(positionKey).find();

        // slot + 3: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        uint256 packed = ((_fees1) << 128) | (_fees0); // tokensOwed0 is lower 128
        vm.store(clPool, bytes32(baseSlot + 3), bytes32(packed));

        // Find the base slot for positions[key] in nfpm (for both lockers)
        uint256 baseSlotLocker = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker.lp()).find();

        // slot + 4: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        packed = ((_fees1) << 128) | (_fees0);
        vm.store(nfpManager, bytes32(baseSlotLocker + 4), bytes32(packed));
    }

    function test_WhenTheRecipientIsTheZeroAddress() external {
        // It should revert with {ZeroAddress}
        _locker = makeAddr("locker");
        _recipient = address(0);

        vm.expectRevert(ILockerFactory.ZeroAddress.selector);
        clLockerFactory.unlock({_locker: _locker, _recipient: _recipient});
    }

    modifier whenTheRecipientIsNotTheZeroAddress() {
        _recipient = users.alice;
        _;
    }

    function test_WhenTheLockerDoesNotExist() external whenTheRecipientIsNotTheZeroAddress {
        // It should revert with {NotLocker}
        _locker = makeAddr("locker");

        vm.expectRevert(ILockerFactory.NotLocker.selector);
        clLockerFactory.unlock({_locker: _locker, _recipient: _recipient});
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
        clLockerFactory.unlock({_locker: _locker, _recipient: _recipient});
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
        clLockerFactory.unlock({_locker: _locker, _recipient: _recipient});
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
        locker.stake();
        // It should revert with {Staked}
        vm.expectRevert(ILockerFactory.Staked.selector);
        clLockerFactory.unlock({_locker: _locker, _recipient: _recipient});
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
        vm.expectEmit({emitter: address(clLockerFactory)});
        emit ILockerFactory.LockerUnlocked({
            locker: _locker,
            underlyingPool: clPool,
            recipient: _recipient,
            refundAddress: _recipient
        });
        clLockerFactory.unlock({_locker: _locker, _recipient: _recipient});

        assertFalse(clLockerFactory.instances(_locker));
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), users.alice);

        assertEq(token0.balanceOf(users.alice) - balance0Before, _fees0);
        assertEq(token1.balanceOf(users.alice) - balance1Before, _fees1);

        _assertMappings(0, address(0), address(0));
    }
}
