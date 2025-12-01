// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract UnstakeIntegrationConcreteTest is V2LockerTest {
    using stdStorage for StdStorage;

    function test_WhenTheLockerIsNotStaked() external {
        // It should revert with {NotStaked}
        vm.startPrank(users.alice);

        vm.expectRevert(ILocker.NotStaked.selector);
        locker.unstake();
    }

    function test_WhenTheLockerIsStaked() external {
        // It should claim the rewards
        // It should withdraw from the gauge
        // It should emit an {Unstaked} event
        vm.startPrank(users.alice);
        locker.stake();
        assertTrue(locker.staked());
        assertEq(IGauge(gauge).balanceOf(address(locker)), locker.lp());

        vm.expectEmit(address(locker));
        emit ILocker.Unstaked();
        locker.unstake();

        assertFalse(locker.staked());
        assertEq(IGauge(gauge).balanceOf(address(locker)), 0);
    }

    function test_WhenTheLockerIsStaked_RewardsClaimFlow() external {
        vm.prank(users.alice);
        locker.stake();

        IERC20 rewardToken = IERC20(IVotingEscrow(IVoter(voter).ve()).token());
        uint256 rewardAmount = 100 * TOKEN_1;
        address notifyAdmin = 0xE6A41fE61E7a1996B59d508661e3f524d6A32075;

        deal(address(rewardToken), notifyAdmin, rewardAmount);
        vm.startPrank(notifyAdmin);
        rewardToken.approve(gauge, rewardAmount);
        IGauge(gauge).notifyRewardWithoutClaim({amount: rewardAmount});
        skip(7 days);
        vm.stopPrank();

        vm.startPrank(users.alice);
        uint256 earned = IGauge(gauge).earned(address(locker));
        vm.expectEmit(gauge);
        emit IGauge.ClaimRewards({from: address(locker), amount: earned});
        vm.expectEmit(address(rewardToken));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: earned});
        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.alice, claimed: earned});
        vm.expectEmit(address(locker));
        emit ILocker.Unstaked();
        locker.unstake();

        assertFalse(locker.staked());
        assertEq(IGauge(gauge).balanceOf(address(locker)), 0);
        assertEq(rewardToken.balanceOf(users.alice), earned);
    }

    function testGas_unstake() external {
        vm.startPrank(users.alice);
        locker.stake();

        locker.unstake();
        vm.snapshotGasLastCall("V2Locker_unstake");
    }
}
