// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract RenounceOwnershipUnitConcreteTest is V2LockerTest {
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

        assertTrue(v2LockerFactory.instances(address(locker)));
        assertEq(v2LockerFactory.locked(v2Pool, 0, 1), lp);
        assertEq(v2LockerFactory.locks(v2Pool), 1);

        // @dev assert lockers mapping and view functions
        address[] memory lockers = v2LockerFactory.lockers(v2Pool);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));

        lockers = v2LockerFactory.lockers(v2Pool, 0, 1);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));
        assertEq(v2LockerFactory.lockersCount(v2Pool), 1);

        // @dev assert lockersPerUser mapping and view functions
        address[] memory lockersPerUser = v2LockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        lockersPerUser = v2LockerFactory.lockersPerUser(users.alice, 0, 1);
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(v2LockerFactory.lockersPerUserCount(users.alice), 1);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        address[] memory lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice);
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice, 0, 1);
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(v2LockerFactory.lockersPerPoolPerUserCount(v2Pool, users.alice), 1);

        vm.expectEmit({emitter: address(locker)});
        emit Ownable.OwnershipTransferred({previousOwner: users.alice, newOwner: address(0)});
        Ownable(address(locker)).renounceOwnership();

        assertEq(Ownable(address(locker)).owner(), address(0));

        assertTrue(v2LockerFactory.instances(address(locker)));
        assertEq(v2LockerFactory.locked(v2Pool, 0, 1), lp);
        assertEq(v2LockerFactory.locks(v2Pool), 1);

        // @dev assert lockers mapping and view functions
        lockers = v2LockerFactory.lockers(v2Pool);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));

        lockers = v2LockerFactory.lockers(v2Pool, 0, 1);
        assertEq(lockers.length, 1);
        assertEq(lockers[0], address(locker));
        assertEq(v2LockerFactory.lockersCount(v2Pool), 1);

        // Assert alice removed from mappings
        // @dev assert lockersPerUser mapping and view functions
        lockersPerUser = v2LockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, 0);
        lockersPerUser = v2LockerFactory.lockersPerUser(users.alice, 0, 1);
        assertEq(lockersPerUser.length, 0);
        assertEq(v2LockerFactory.lockersPerUserCount(users.alice), 0);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice);
        assertEq(lockersPerPoolPerUser.length, 0);
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice, 0, 1);
        assertEq(lockersPerPoolPerUser.length, 0);
        assertEq(v2LockerFactory.lockersPerPoolPerUserCount(v2Pool, users.alice), 0);

        // Assert address(0) added to mappings
        // @dev assert lockersPerUser mapping and view functions
        lockersPerUser = v2LockerFactory.lockersPerUser(address(0));
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        lockersPerUser = v2LockerFactory.lockersPerUser(address(0), 0, 1);
        assertEq(lockersPerUser.length, 1);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(v2LockerFactory.lockersPerUserCount(address(0)), 1);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, address(0));
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, address(0), 0, 1);
        assertEq(lockersPerPoolPerUser.length, 1);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(v2LockerFactory.lockersPerPoolPerUserCount(v2Pool, address(0)), 1);
    }
}
