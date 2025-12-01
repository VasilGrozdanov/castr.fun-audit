// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract RenounceOwnershipUnitConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

    function test_WhenTheCallerIsNotOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        vm.prank(users.charlie);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.charlie));
        Ownable(address(locker)).renounceOwnership();
    }

    function test_WhenTheCallerIsOwner() external {
        // It should update the locker factory mappings
        // It should transfer ownership to address zero
        // It should emit a {OwnershipTransferred} event
        vm.startPrank(users.alice);

        (,,,,,,, uint128 liquidity,,,,) = INfpm(nfpManager).positions({tokenId: lp});
        assertTrue(clLockerFactory.instances(address(locker)));
        assertEq(clLockerFactory.locked(clPool, 0, 1), liquidity);
        assertEq(clLockerFactory.locks(clPool), 1);

        // @dev assert lockers mapping and view functions
        address[] memory lockers = clLockerFactory.lockers(clPool);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));

        lockers = clLockerFactory.lockers(clPool, 0, 1);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));
        assertEq(clLockerFactory.lockersCount(clPool), 1);

        // @dev assert lockersPerUser mapping and view functions
        address[] memory lockersPerUser = clLockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        lockersPerUser = clLockerFactory.lockersPerUser(users.alice, 0, 1);
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(clLockerFactory.lockersPerUserCount(users.alice), 1);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        address[] memory lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, users.alice);
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, users.alice, 0, 1);
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(clLockerFactory.lockersPerPoolPerUserCount(clPool, users.alice), 1);

        vm.expectEmit({emitter: address(locker)});
        emit Ownable.OwnershipTransferred({previousOwner: users.alice, newOwner: address(0)});
        Ownable(address(locker)).renounceOwnership();

        assertEq(Ownable(address(locker)).owner(), address(0));

        assertTrue(clLockerFactory.instances(address(locker)));
        assertEq(clLockerFactory.locked(clPool, 0, 1), liquidity);
        assertEq(clLockerFactory.locks(clPool), 1);

        // @dev assert lockers mapping and view functions
        lockers = clLockerFactory.lockers(clPool);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));

        lockers = clLockerFactory.lockers(clPool, 0, 1);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));
        assertEq(clLockerFactory.lockersCount(clPool), 1);

        // Assert alice removed from mappings
        // @dev assert lockersPerUser mapping and view functions
        lockersPerUser = clLockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, 0);
        lockersPerUser = clLockerFactory.lockersPerUser(users.alice, 0, 1);
        assertEq(lockersPerUser.length, 0);
        assertEq(clLockerFactory.lockersPerUserCount(users.alice), 0);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, users.alice);
        assertEq(lockersPerPoolPerUser.length, 0);
        lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, users.alice, 0, 1);
        assertEq(lockersPerPoolPerUser.length, 0);
        assertEq(clLockerFactory.lockersPerPoolPerUserCount(clPool, users.alice), 0);

        // Assert address(0) added to mappings
        // @dev assert lockersPerUser mapping and view functions
        lockersPerUser = clLockerFactory.lockersPerUser(address(0));
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        lockersPerUser = clLockerFactory.lockersPerUser(address(0), 0, 1);
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(clLockerFactory.lockersPerUserCount(address(0)), 1);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, address(0));
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        lockersPerPoolPerUser = clLockerFactory.lockersPerPoolPerUser(clPool, address(0), 0, 1);
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(clLockerFactory.lockersPerPoolPerUserCount(clPool, address(0)), 1);
    }
}
