// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract IncreaseDurationIntegrationConcreteTest is CLLockerTest {
    uint32 public _duration;

    function test_WhenCallerIsNotOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.charlie));
        locker.increaseDuration({_duration: _duration});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheDurationIsZero() external whenCallerIsOwner {
        // It should revert with {ZeroDuration}
        vm.expectRevert(ILocker.ZeroDuration.selector);
        locker.increaseDuration({_duration: _duration});
    }

    modifier whenTheDurationIsNotZero() {
        _duration = 52 weeks;
        _;
    }

    function test_WhenTheLockerIsUnlocked() external whenCallerIsOwner whenTheDurationIsNotZero {
        // It should revert with {NotLocked}
        uint256 _timeskip = lockDuration;
        skip(_timeskip);

        vm.expectRevert(ILocker.NotLocked.selector);
        locker.increaseDuration({_duration: _duration});
    }

    modifier whenTheLockerIsLocked() {
        _;
    }

    function test_WhenTheLockerIsPermanentlyLocked()
        external
        whenCallerIsOwner
        whenTheDurationIsNotZero
        whenTheLockerIsLocked
    {
        // It should revert with {PermanentLock}
        /// @dev Permanently lock liquidity
        locker.increaseDuration({_duration: type(uint32).max});

        vm.expectRevert(ILocker.PermanentLock.selector);
        locker.increaseDuration({_duration: _duration});
    }

    modifier whenTheLockerIsNotPermanentlyLocked() {
        _;
    }

    function test_WhenTheDurationIsUINT32_MAX()
        external
        whenCallerIsOwner
        whenTheDurationIsNotZero
        whenTheLockerIsLocked
        whenTheLockerIsNotPermanentlyLocked
    {
        // It should permanently lock the liquidity
        // It should emit an {UnlockTimestampIncreased} event
        vm.expectEmit({emitter: address(locker)});
        emit ILocker.UnlockTimestampIncreased({newUnlockTimestamp: type(uint32).max});
        locker.increaseDuration({_duration: type(uint32).max});

        assertEq(locker.lockedUntil(), type(uint32).max);
    }

    function test_WhenTheDurationIsNotUINT32_MAX()
        external
        whenCallerIsOwner
        whenTheDurationIsNotZero
        whenTheLockerIsLocked
        whenTheLockerIsNotPermanentlyLocked
    {
        // It should increase the unlock timestamp
        // It should emit an {UnlockTimestampIncreased} event
        uint256 oldLockedUntil = locker.lockedUntil();

        vm.expectEmit({emitter: address(locker)});
        emit ILocker.UnlockTimestampIncreased({newUnlockTimestamp: oldLockedUntil + _duration});
        locker.increaseDuration({_duration: _duration});

        assertEq(locker.lockedUntil(), oldLockedUntil + _duration);
    }

    function testGas_increaseDuration()
        external
        whenCallerIsOwner
        whenTheDurationIsNotZero
        whenTheLockerIsLocked
        whenTheLockerIsNotPermanentlyLocked
    {
        locker.increaseDuration({_duration: _duration});
        vm.snapshotGasLastCall("CLLocker_increaseDuration");
    }
}
