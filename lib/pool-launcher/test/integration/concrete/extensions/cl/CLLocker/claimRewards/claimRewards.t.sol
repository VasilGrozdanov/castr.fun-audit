// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract ClaimRewardsIntegrationConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

    IERC20 public rewardToken;
    uint256 public rewardAmount;
    address public notifyAdmin;
    ICLLocker public locker2; // with beneficiary

    function setUp() public override {
        super.setUp();

        rewardToken = IERC20(IVotingEscrow(IVoter(voter).ve()).token());
        rewardAmount = 100 * TOKEN_1;
        notifyAdmin = 0xE6A41fE61E7a1996B59d508661e3f524d6A32075;

        //mint lp2
        deal(poolLauncherToken, address(users.alice), poolLauncherAmount);
        deal(tokenToPair, address(users.alice), usdcAmount);

        vm.startPrank(users.alice);
        uint256 lp = mintLP({
            token0: poolLauncherToken < tokenToPair ? poolLauncherToken : tokenToPair,
            token1: poolLauncherToken < tokenToPair ? tokenToPair : poolLauncherToken,
            tickSpacing: TICK_SPACING_200,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0: poolLauncherToken < tokenToPair ? poolLauncherAmount : usdcAmount,
            amount1: poolLauncherToken < tokenToPair ? usdcAmount : poolLauncherAmount,
            recipient: users.alice
        });

        //lock lp2 in locker factory (locker2)
        // will get rewardAmount/2 - 10%
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: lp});
        address lockerAddress = clLockerFactory.lock({
            _lp: lp,
            _lockUntil: uint32(block.timestamp + (365 days / 2)),
            _beneficiary: users.bob,
            _beneficiaryShare: 1000, // 10%
            _bribeableShare: 0,
            _owner: users.alice
        });
        locker2 = ICLLocker(lockerAddress);

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
        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.alice, claimed: rewardAmount / 2});
        uint256 claimed = locker.claimRewards({_recipient: users.alice});

        assertEq(claimed, rewardAmount / 2);
        assertEq(rewardToken.balanceOf(users.alice), rewardAmount / 2);
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
        rewardAmount = IGauge(gauge).earned({account: address(locker), tokenId: locker.lp()});
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
        vm.startPrank(users.alice);

        uint256 totalReward = rewardAmount / 2;
        uint256 bobReward = totalReward * 10 / 100;
        uint256 aliceReward = totalReward - bobReward;

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

    function testGas_claimRewards() external whenTheLockerIsStaked whenTheAmountOfRewardsIsGreaterThanZero {
        vm.startPrank(users.alice);

        locker.claimRewards({_recipient: users.alice});
        vm.snapshotGasLastCall("CLLocker_claimRewards");
    }
}
