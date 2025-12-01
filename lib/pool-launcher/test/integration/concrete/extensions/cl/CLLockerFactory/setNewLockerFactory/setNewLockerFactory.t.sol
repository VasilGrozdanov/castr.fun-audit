// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLockerFactory.t.sol";

contract SetNewLockerFactoryIntegrationConcreteTest is CLLockerFactoryTest {
    function test_WhenCallerIsNotOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, users.charlie));
        clLockerFactory.setNewLockerFactory({_lockerFactory: users.charlie});
    }

    modifier whenCallerIsOwner() {
        _;
    }

    function test_WhenTheNewLockerFactoryIsTheZeroAddress() external whenCallerIsOwner {
        // It should revert with {ZeroAddress}
        vm.prank(users.owner);
        vm.expectRevert(ILockerFactory.ZeroAddress.selector);
        clLockerFactory.setNewLockerFactory({_lockerFactory: address(0)});
    }

    function test_WhenTheNewLockerFactoryIsNotTheZeroAddress() external whenCallerIsOwner {
        // It should set the new locker factory
        // It should emit a {NewLockerFactorySet} event
        address _newLockerFactory = makeAddr("lockerFactory");

        vm.prank(users.owner);
        vm.expectEmit({emitter: address(clLockerFactory)});
        emit ILockerFactory.NewLockerFactorySet({lockerFactory: _newLockerFactory});
        clLockerFactory.setNewLockerFactory({_lockerFactory: _newLockerFactory});

        assertEq(clLockerFactory.newLockerFactory(), _newLockerFactory);
    }
}
