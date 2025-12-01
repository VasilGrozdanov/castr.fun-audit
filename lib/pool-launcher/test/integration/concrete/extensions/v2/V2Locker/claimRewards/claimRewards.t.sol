// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract ClaimRewardsIntegrationConcreteTest is V2LockerTest {
    using stdStorage for StdStorage;

    IERC20 public rewardToken;
    uint256 public rewardAmount;
    address public notifyAdmin;
    IV2Locker public locker2; // with beneficiary

    function setUp() public override {
        super.setUp();

        rewardToken = IERC20(IVotingEscrow(IVoter(voter).ve()).token());
        rewardAmount = 100 * TOKEN_1;
        notifyAdmin = 0xE6A41fE61E7a1996B59d508661e3f524d6A32075;

        vm.startPrank(users.alice);
        //mint lp2
        deal(poolLauncherToken, v2Pool, poolLauncherAmount * 4);
        deal(tokenToPair, v2Pool, usdcAmount * 4);
        uint256 lp = IV2Pool(v2Pool).mint({to: users.alice});
        IV2Pool(v2Pool).skim({to: users.alice});

        //lock lp2 in locker factory (locker2)
        IERC20(v2Pool).approve({spender: address(v2LockerFactory), value: lp});
        address lockerAddress = v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + (365 days / 2)),
            _beneficiary: users.bob,
            _beneficiaryShare: 1000, // 10%
            _bribeableShare: 0,
            _owner: users.alice
        });
        locker2 = IV2Locker(lockerAddress);

        vm.stopPrank();
    }

    function test_WhenTheLockerIsNotStaked() external {
        // It should revert with {NotStaked}
        vm.startPrank(users.alice);
        vm.expectRevert(ILocker.NotStaked.selector);
        locker.claimRewards({_recipient: users.alice});
    }

    modifier whenTheLockerIsStaked() {
        vm.startPrank(users.alice);
        locker.stake();
        locker2.stake();
        _;
    }

    function test_WhenTheAmountOfRewardsIsZero() external whenTheLockerIsStaked {
        // It should keep the same locker balance
        // It should keep the same user balance
        vm.startPrank(users.alice);
        uint256 rewardTokenBalanceBefore = rewardToken.balanceOf(address(locker));
        uint256 userRewardTokenBalanceBefore = rewardToken.balanceOf(users.alice);

        uint256 claimed = locker.claimRewards({_recipient: users.alice});

        uint256 rewardTokenBalanceAfter = rewardToken.balanceOf(address(locker));
        uint256 userRewardTokenBalanceAfter = rewardToken.balanceOf(users.alice);

        assertEq(claimed, 0);
        assertEq(rewardTokenBalanceBefore, rewardTokenBalanceAfter);
        assertEq(userRewardTokenBalanceBefore, userRewardTokenBalanceAfter);
    }

    modifier whenTheAmountOfRewardsIsGreaterThanZero() {
        deal(address(rewardToken), notifyAdmin, rewardAmount);
        vm.startPrank(notifyAdmin);
        rewardToken.approve(gauge, rewardAmount);
        IGauge(gauge).notifyRewardWithoutClaim({amount: rewardAmount});
        skip(7 days);
        vm.stopPrank();
        _;
    }

    function test_WhenTheBeneficiaryIsAddressZero()
        external
        whenTheLockerIsStaked
        whenTheAmountOfRewardsIsGreaterThanZero
    {
        // It should claim from the gauge
        // It should send the rewards to the recipient
        // It should emit a {RewardsClaimed} for the recipient
        uint256 aliceReward = rewardAmount / 4;

        vm.startPrank(users.alice);
        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.alice, claimed: 24999999999999901581});
        uint256 claimed = locker.claimRewards({_recipient: users.alice});

        assertApproxEqAbs(claimed, aliceReward, 2e8);
        assertApproxEqAbs(rewardToken.balanceOf(users.alice), aliceReward, 2e8);
    }

    modifier whenTheBeneficiaryIsNotAddressZero() {
        locker = locker2;
        _;
    }

    function test_WhenBeneficiaryShareIsZero()
        external
        whenTheLockerIsStaked
        whenTheAmountOfRewardsIsGreaterThanZero
        whenTheBeneficiaryIsNotAddressZero
    {
        // It should claim the rewards
        // It should send the rewards to the recipient
        // It should emit a {RewardsClaimed} for the recipient

        /// @dev make rewardAmount small enough for beneficiary share to be zero
        rewardAmount = 9;

        /// @dev reset claimable rewards
        vm.prank(users.alice);
        locker.claimRewards({_recipient: users.alice});
        deal(address(rewardToken), users.alice, 0);
        deal(address(rewardToken), users.bob, 0);

        /// @dev skip to last seconds of epoch to avoid ZeroRewardRate error
        uint256 epochNext = block.timestamp - (block.timestamp % 7 days) + 7 days;
        uint256 timeUntilNext = epochNext - block.timestamp;
        skip(timeUntilNext - rewardAmount);

        deal(address(rewardToken), notifyAdmin, rewardAmount);
        vm.startPrank(notifyAdmin);
        rewardToken.approve(gauge, rewardAmount);
        IGauge(gauge).notifyRewardWithoutClaim({amount: rewardAmount});
        skip(7 days);
        vm.stopPrank();

        /// @dev check actual reward amount
        rewardAmount = IGauge(gauge).earned({_account: address(locker)});
        assertGt(rewardAmount, 0);

        vm.startPrank(users.alice);
        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.alice, claimed: rewardAmount});

        uint256 claimed = locker.claimRewards({_recipient: users.alice});

        assertEq(claimed, rewardAmount);
        assertEq(rewardToken.balanceOf(users.alice), rewardAmount);
        assertEq(rewardToken.balanceOf(users.bob), 0);
        assertEq(rewardToken.balanceOf(address(locker)), 0);
    }

    function test_WhenTheBeneficiaryShareIsGreaterThanZero()
        external
        whenTheLockerIsStaked
        whenTheAmountOfRewardsIsGreaterThanZero
        whenTheBeneficiaryIsNotAddressZero
    {
        // It should claim the rewards
        // It should send a share to the beneficiary
        // It should emit a {RewardsClaimed} for the beneficiary
        // It should send the rewards to the recipient
        // It should emit a {RewardsClaimed} for the recipient
        rewardAmount = IGauge(gauge).earned({_account: address(locker)});
        assertGt(rewardAmount, 0);
        uint256 bobReward = rewardAmount / 10;
        uint256 aliceReward = rewardAmount - bobReward;

        vm.startPrank(users.alice);
        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.bob, claimed: bobReward});
        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.alice, claimed: aliceReward});

        uint256 claimed = locker.claimRewards({_recipient: users.alice});

        assertEq(claimed, aliceReward);
        assertEq(rewardToken.balanceOf(users.alice), aliceReward);
        assertEq(rewardToken.balanceOf(users.bob), bobReward);
        assertEq(rewardToken.balanceOf(address(locker)), 0);
    }

    function testGas_claimRewards()
        external
        whenTheLockerIsStaked
        whenTheAmountOfRewardsIsGreaterThanZero
        whenTheBeneficiaryIsNotAddressZero
    {
        vm.startPrank(users.alice);

        locker.claimRewards({_recipient: users.alice});
        vm.snapshotGasLastCall("V2Locker_claimRewards");
    }
}
