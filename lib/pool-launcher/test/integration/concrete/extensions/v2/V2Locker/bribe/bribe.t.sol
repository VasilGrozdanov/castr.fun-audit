// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract BribeIntegrationConcreteTest is V2LockerTest {
    using stdStorage for StdStorage;

    IERC20 public token0;
    IERC20 public token1;
    uint256 public fees0;
    uint256 public fees1;

    IERC20 public rewardToken;
    uint256 public rewardAmount;
    address public notifyAdmin;

    uint16 beneficiaryShare = 1000; // 10%
    uint16 bribeableShare = 2000; // 20%

    address bribeContract;
    IV2Locker public locker2; // with beneficiary and bribeable share

    uint16 percentage;

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));
        (fees0, fees1) =
            poolLauncherToken < tokenToPair ? (poolLauncherAmount, usdcAmount) : (usdcAmount, poolLauncherAmount);

        rewardToken = IERC20(IVotingEscrow(IVoter(voter).ve()).token());
        rewardAmount = 100 * TOKEN_1;
        notifyAdmin = 0xE6A41fE61E7a1996B59d508661e3f524d6A32075;

        bribeContract = IVoter(voter).gaugeToBribe(gauge);

        vm.startPrank(users.alice);
        //mint lp
        deal(poolLauncherToken, v2Pool, poolLauncherAmount * 4);
        deal(tokenToPair, v2Pool, usdcAmount * 4);
        uint256 lp = IV2Pool(v2Pool).mint({to: users.alice});
        IV2Pool(v2Pool).skim({to: users.alice});

        //lock lp with beneficiary and bribeable share
        IERC20(v2Pool).approve({spender: address(v2LockerFactory), value: lp});
        address lockerAddress = v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare,
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
        locker2 = IV2Locker(lockerAddress);
        vm.stopPrank();
    }

    function _mockFees(uint256 _fees0, uint256 _fees1) internal {
        (fees0, fees1) = (_fees0, _fees1);
        address poolFees = IV2Pool(v2Pool).poolFees();
        deal(address(token0), poolFees, fees0);
        deal(address(token1), poolFees, fees1);
        stdstore.target({_target: v2Pool}).sig("claimable0(address)").with_key(address(locker)).checked_write(fees0);
        stdstore.target({_target: v2Pool}).sig("claimable1(address)").with_key(address(locker)).checked_write(fees1);
    }

    function _mockRewards(uint256 _rewardAmount) internal {
        /// @dev skip to last seconds of epoch to avoid ZeroRewardRate error
        uint256 epochNext = block.timestamp - (block.timestamp % 7 days) + 7 days;
        uint256 timeUntilNext = epochNext - block.timestamp;
        if (timeUntilNext > _rewardAmount) skip(timeUntilNext - _rewardAmount);

        deal(address(rewardToken), notifyAdmin, _rewardAmount);
        vm.startPrank(notifyAdmin);
        rewardToken.approve(gauge, _rewardAmount);
        IGauge(gauge).notifyRewardWithoutClaim({amount: _rewardAmount});
        skip(7 days);
        vm.stopPrank();

        /// @dev actual reward amount differs slightly
        rewardAmount = IGauge(gauge).earned({_account: address(locker)});
        assertApproxEqAbs(rewardAmount, _rewardAmount, 1e6);
        assertGt(rewardAmount, 0);
    }

    function test_InitialState() public view override {
        assertEq(Ownable(address(locker2)).owner(), users.alice);
        assertEq(locker2.MAX_BPS(), MAX_BPS);
        assertEq(address(locker2.voter()), voter);
        assertEq(locker2.factory(), address(v2LockerFactory));
        assertEq(uint8(locker2.poolType()), uint8(ILockerFactory.PoolType.BASIC));
        assertEq(locker2.pool(), v2Pool);
        assertEq(locker2.token0(), address(token));
        assertEq(locker2.token1(), address(usdc));
        assertEq(locker2.rewardToken(), IVotingEscrow(MockVoter(voter).ve()).token());
        assertEq(locker2.lp(), 3e18);
        assertEq(locker2.beneficiary(), users.bob);
        assertEq(locker2.beneficiaryShare(), beneficiaryShare);
        assertFalse(locker2.root());
        assertEq(address(locker2.gauge()), address(0));
        assertEq(locker2.bribeableShare(), bribeableShare);
        assertEq(locker2.lockedUntil(), block.timestamp + lockDuration);
        assertFalse(locker2.staked());
    }

    function test_WhenCallerIsNotOwner() external {
        // It should revert with {OwnableUnauthorizedAccount}
        address _caller = users.charlie;

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        locker.bribe({_percentage: 0});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function test_WhenTheLockerIsNotLocked() external whenCallerIsOwner {
        // It should revert with {NotLocked}
        skip(lockDuration);
        v2LockerFactory.unlock({_locker: address(locker), _recipient: users.alice});
        vm.expectRevert(ILocker.NotLocked.selector);
        locker.bribe({_percentage: 0});
    }

    modifier whenTheLockerIsLocked() {
        _;
    }

    function test_WhenThereIsNoGaugeForThePool() external whenCallerIsOwner whenTheLockerIsLocked {
        // It should revert with {NoGauge}
        vm.mockCall(voter, abi.encodeWithSelector(IVoter.gauges.selector), abi.encode(address(0)));
        vm.expectRevert(ILocker.NoGauge.selector);
        locker.bribe({_percentage: 0});
    }

    modifier whenThereIsAGaugeForThePool() {
        _;
    }

    function test_WhenThePercentageIsGreaterThanBribeableShare()
        external
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
    {
        // It should revert with {InvalidPercentage}
        uint16 _percentage = bribeableShare + 1;
        vm.expectRevert(ILocker.InvalidPercentage.selector);
        locker.bribe({_percentage: _percentage});
    }

    modifier whenThePercentageIsSmallerOrEqualToBribeableShare() {
        percentage = locker.bribeableShare();
        _;
    }

    modifier whenTheLockerIsStaked() {
        locker.stake();
        _;
    }

    modifier whenTheBeneficiaryIsAddressZero() {
        assertEq(locker.beneficiary(), address(0));
        _;
    }

    function test_WhenTheBribeAmountIsZero()
        external
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsStaked
        whenTheBeneficiaryIsAddressZero
    {
        // It should claim the rewards
        // It should send the rewards to the owner
        /// @dev small rewards for bribe amount to be zero
        uint256 _rewardAmount = 2;
        _mockRewards(_rewardAmount);

        vm.startPrank(users.alice);

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, rewardAmount);
        assertEq(balanceBribe, 0);
    }

    function test_WhenTheBribeAmountIsNotZero()
        external
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsStaked
        whenTheBeneficiaryIsAddressZero
    {
        // It should claim the rewards
        // It should bribe the bribe amount
        // It should emit a {Bribed} event
        // It should send the remaning rewards to the owner
        _mockRewards(rewardAmount);

        uint256 expectedBribe = rewardAmount * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBribe;

        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(rewardToken), amount: expectedBribe});

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, expectedOwner);
        assertEq(balanceBribe, expectedBribe);
    }

    modifier whenTheBeneficiaryIsNotAddressZero() {
        locker = locker2;
        _;
    }

    modifier whenTheBeneficiaryShareIsZero() {
        _;
    }

    function test_WhenTheBribeAmountIsZero_()
        external
        whenTheBeneficiaryIsNotAddressZero
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsStaked
        whenTheBeneficiaryShareIsZero
    {
        // It should claim the rewards
        // It should send the rewards to the owner
        /// @dev small rewards for bribe amount to be zero
        uint256 _rewardAmount = 5;
        _mockRewards(_rewardAmount);
        assertLt(rewardAmount, 5);

        vm.startPrank(users.alice);

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBeneficiary = rewardToken.balanceOf(users.bob);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, rewardAmount);
        assertEq(balanceBeneficiary, 0);
        assertEq(balanceBribe, 0);
    }

    function test_WhenTheBribeAmountIsNotZero_()
        external
        whenTheBeneficiaryIsNotAddressZero
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsStaked
        whenTheBeneficiaryShareIsZero
    {
        // It should claim the rewards
        // It should bribe the bribe amount
        // It should emit a {Bribed} event
        // It should send the remaining rewards to the owner

        uint256 _rewardAmount = 9;
        // beneficiary 10% is 0
        // bribe percentage 20% is ~1,8
        _mockRewards(_rewardAmount);
        assertLt(rewardAmount, 10);
        assertGe(rewardAmount, 5);

        uint256 expectedBribe = rewardAmount * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBribe;

        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(rewardToken), amount: expectedBribe});

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBeneficiary = rewardToken.balanceOf(users.bob);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, expectedOwner);
        assertEq(balanceBeneficiary, 0);
        assertEq(balanceBribe, expectedBribe);
    }

    modifier whenTheBeneficiaryShareIsGreaterThanZero() {
        _;
    }

    function test_WhenTheBribeAmountIsZero__()
        external
        whenTheBeneficiaryIsNotAddressZero
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsStaked
        whenTheBeneficiaryShareIsGreaterThanZero
    {
        // It should claim the rewards
        // It should send a share to the beneficiary
        // It should emit a {RewardsClaimed} for the beneficiary
        // It should send the remaining rewards to the owner
        /// @dev percentage small enough to have beneficiary share and bribe amount still zero
        percentage = 1;
        uint256 _rewardAmount = 100;
        // beneficiary 10% is > 0
        // bribe percentage 1% is < 1
        _mockRewards(_rewardAmount);
        assertLt(rewardAmount, 100);
        assertGe(rewardAmount, 10);

        uint256 expectedBeneficiary = rewardAmount * beneficiaryShare / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBeneficiary;

        vm.startPrank(users.alice);

        vm.expectCall({callee: gauge, data: abi.encodeWithSelector(IGauge.notifyRewardWithoutClaim.selector), count: 0});
        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.bob, claimed: expectedBeneficiary});

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBeneficiary = rewardToken.balanceOf(users.bob);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, expectedOwner);
        assertEq(balanceBeneficiary, expectedBeneficiary);
        assertEq(balanceBribe, 0);
    }

    function test_WhenTheBribeAmountIsNotZero__()
        external
        whenTheBeneficiaryIsNotAddressZero
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsStaked
        whenTheBeneficiaryShareIsGreaterThanZero
    {
        // It should claim the rewards
        // It should send a share to the beneficiary
        // It should emit a {RewardsClaimed} for the beneficiary
        // It should bribe the bribe amount
        // It should emit a {Bribed} event
        // It should send the remaining rewards to the owner
        _mockRewards(rewardAmount);

        uint256 expectedBeneficiary = rewardAmount * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe = (rewardAmount - expectedBeneficiary) * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBeneficiary - expectedBribe;

        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.bob, claimed: expectedBeneficiary});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(rewardToken), amount: expectedBribe});

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBeneficiary = rewardToken.balanceOf(users.bob);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, expectedOwner);
        assertEq(balanceBeneficiary, expectedBeneficiary);
        assertEq(balanceBribe, expectedBribe);
    }

    modifier whenTheLockerIsNotStaked() {
        _;
    }

    modifier whenTheBeneficiaryIsAddressZero_() {
        _;
    }

    function test_WhenTheBribeAmountIsZero___()
        external
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryIsAddressZero_
    {
        // It should claim the fees
        // It should send the fees to the owner
        /// @dev small fees for bribe amount to be zero
        uint256 _fees0 = 2;
        uint256 _fees1 = 2;
        _mockFees({_fees0: _fees0, _fees1: _fees1});

        uint256 expectedLocker0 = 0;
        uint256 expectedLocker1 = 0;
        uint256 expectedOwner0 = fees0;
        uint256 expectedOwner1 = fees1;
        uint256 expectedBribe0 = 0;
        uint256 expectedBribe1 = 0;

        vm.expectCall({callee: gauge, data: abi.encodeWithSelector(IGauge.notifyRewardWithoutClaim.selector), count: 0});

        locker.bribe({_percentage: percentage});

        uint256 balanceLocker0 = token0.balanceOf(address(locker));
        uint256 balanceLocker1 = token1.balanceOf(address(locker));
        uint256 balanceOwner0 = token0.balanceOf(users.alice);
        uint256 balanceOwner1 = token1.balanceOf(users.alice);
        uint256 balanceBribe0 = token0.balanceOf(bribeContract);
        uint256 balanceBribe1 = token1.balanceOf(bribeContract);
        assertEq(balanceLocker0, expectedLocker0);
        assertEq(balanceLocker1, expectedLocker1);
        assertEq(balanceOwner0, expectedOwner0);
        assertEq(balanceOwner1, expectedOwner1);
        assertEq(balanceBribe0, expectedBribe0);
        assertEq(balanceBribe1, expectedBribe1);
    }

    function test_WhenTheBribeAmountIsNotZero___()
        external
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryIsAddressZero_
    {
        // It should claim the fees
        // It should bribe the bribe amount
        // It should emit a {Bribed} event
        // It should send the remaning fees to the owner
        _mockFees({_fees0: fees0, _fees1: fees1});

        uint256 expectedBribe0 = fees0 * percentage / MAX_BPS;
        uint256 expectedBribe1 = fees1 * percentage / MAX_BPS;
        uint256 expectedOwner0 = fees0 - expectedBribe0;
        uint256 expectedOwner1 = fees1 - expectedBribe1;

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(token0), amount: expectedBribe0});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(token1), amount: expectedBribe1});

        locker.bribe({_percentage: percentage});

        uint256 balanceLocker0 = token0.balanceOf(address(locker));
        uint256 balanceLocker1 = token1.balanceOf(address(locker));
        uint256 balanceOwner0 = token0.balanceOf(users.alice);
        uint256 balanceOwner1 = token1.balanceOf(users.alice);
        uint256 balanceBribe0 = token0.balanceOf(bribeContract);
        uint256 balanceBribe1 = token1.balanceOf(bribeContract);
        assertEq(balanceLocker0, 0);
        assertEq(balanceLocker1, 0);
        assertEq(balanceOwner0, expectedOwner0);
        assertEq(balanceOwner1, expectedOwner1);
        assertEq(balanceBribe0, expectedBribe0);
        assertEq(balanceBribe1, expectedBribe1);
    }

    modifier whenTheBeneficiaryIsNotAddressZero_() {
        locker = locker2;
        _;
    }

    modifier whenTheBeneficiaryShareIsZero_() {
        _;
    }

    function test_WhenTheBribeAmountIsZero____()
        external
        whenTheBeneficiaryIsNotAddressZero_
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryShareIsZero_
    {
        // It should claim the fees
        // It should send the fees to the owner

        /// @dev small fees for bribe amount to be zero
        uint256 _fees0 = 4;
        uint256 _fees1 = 4;
        _mockFees({_fees0: _fees0, _fees1: _fees1});

        uint256 expectedBribe0 = 0;
        uint256 expectedBribe1 = 0;
        uint256 expectedBeneficiary0 = 0;
        uint256 expectedBeneficiary1 = 0;
        uint256 expectedOwner0 = fees0;
        uint256 expectedOwner1 = fees1;

        vm.expectCall({callee: gauge, data: abi.encodeWithSelector(IGauge.notifyRewardWithoutClaim.selector), count: 0});

        locker.bribe({_percentage: percentage});

        uint256 balanceLocker0 = token0.balanceOf(address(locker));
        uint256 balanceLocker1 = token1.balanceOf(address(locker));
        uint256 balanceOwner0 = token0.balanceOf(users.alice);
        uint256 balanceOwner1 = token1.balanceOf(users.alice);
        uint256 balanceBeneficiary0 = token0.balanceOf(users.bob);
        uint256 balanceBeneficiary1 = token1.balanceOf(users.bob);
        uint256 balanceBribe0 = token0.balanceOf(bribeContract);
        uint256 balanceBribe1 = token1.balanceOf(bribeContract);
        assertEq(balanceLocker0, 0);
        assertEq(balanceLocker1, 0);
        assertEq(balanceOwner0, expectedOwner0);
        assertEq(balanceOwner1, expectedOwner1);
        assertEq(balanceBeneficiary0, expectedBeneficiary0);
        assertEq(balanceBeneficiary1, expectedBeneficiary1);
        assertEq(balanceBribe0, expectedBribe0);
        assertEq(balanceBribe1, expectedBribe1);
    }

    function test_WhenTheBribeAmountIsNotZero____()
        external
        whenTheBeneficiaryIsNotAddressZero_
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryShareIsZero_
    {
        // It should claim the fees
        // It should bribe the bribe amount
        // It should emit a {Bribed} event
        // It should send the remaining fees to the owner

        uint256 _fees0 = 9;
        uint256 _fees1 = 9;
        // beneficiary 10% is 0
        // bribe percentage 20% is ~1,8
        _mockFees({_fees0: _fees0, _fees1: _fees1});

        uint256 expectedBribe0 = fees0 * percentage / MAX_BPS;
        uint256 expectedBribe1 = fees1 * percentage / MAX_BPS;
        uint256 expectedBeneficiary0 = 0;
        uint256 expectedBeneficiary1 = 0;
        uint256 expectedOwner0 = fees0 - expectedBribe0;
        uint256 expectedOwner1 = fees1 - expectedBribe1;

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(token0), amount: expectedBribe0});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(token1), amount: expectedBribe1});

        locker.bribe({_percentage: percentage});

        uint256 balanceLocker0 = token0.balanceOf(address(locker));
        uint256 balanceLocker1 = token1.balanceOf(address(locker));
        uint256 balanceOwner0 = token0.balanceOf(users.alice);
        uint256 balanceOwner1 = token1.balanceOf(users.alice);
        uint256 balanceBeneficiary0 = token0.balanceOf(users.bob);
        uint256 balanceBeneficiary1 = token1.balanceOf(users.bob);
        uint256 balanceBribe0 = token0.balanceOf(bribeContract);
        uint256 balanceBribe1 = token1.balanceOf(bribeContract);
        assertEq(balanceLocker0, 0);
        assertEq(balanceLocker1, 0);
        assertEq(balanceOwner0, expectedOwner0);
        assertEq(balanceOwner1, expectedOwner1);
        assertEq(balanceBeneficiary0, expectedBeneficiary0);
        assertEq(balanceBeneficiary1, expectedBeneficiary1);
        assertEq(balanceBribe0, expectedBribe0);
        assertEq(balanceBribe1, expectedBribe1);
    }

    modifier whenTheBeneficiaryShareIsGreaterThanZero_() {
        _;
    }

    function test_WhenTheBribeAmountIsZero_____()
        external
        whenTheBeneficiaryIsNotAddressZero_
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryShareIsGreaterThanZero_
    {
        // It should claim the fees
        // It should send a share to the beneficiary
        // It should emit a {FeesClaimed} for the beneficiary
        // It should send the remaining fees to the owner
        percentage = 1;
        uint256 _fees0 = 100;
        uint256 _fees1 = 100;
        // beneficiary 10% is > 0
        // bribe percentage 1% is < 1
        _mockFees({_fees0: _fees0, _fees1: _fees1});

        uint256 expectedBribe0 = 0;
        uint256 expectedBribe1 = 0;
        uint256 expectedBeneficiary0 = fees0 * beneficiaryShare / MAX_BPS;
        uint256 expectedBeneficiary1 = fees1 * beneficiaryShare / MAX_BPS;
        uint256 expectedOwner0 = fees0 - expectedBeneficiary0;
        uint256 expectedOwner1 = fees1 - expectedBeneficiary1;

        vm.expectCall({callee: gauge, data: abi.encodeWithSelector(IGauge.notifyRewardWithoutClaim.selector), count: 0});

        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.bob, claimed0: expectedBeneficiary0, claimed1: expectedBeneficiary1});

        locker.bribe({_percentage: percentage});

        uint256 balanceLocker0 = token0.balanceOf(address(locker));
        uint256 balanceLocker1 = token1.balanceOf(address(locker));
        uint256 balanceOwner0 = token0.balanceOf(users.alice);
        uint256 balanceOwner1 = token1.balanceOf(users.alice);
        uint256 balanceBeneficiary0 = token0.balanceOf(users.bob);
        uint256 balanceBeneficiary1 = token1.balanceOf(users.bob);
        uint256 balanceBribe0 = token0.balanceOf(bribeContract);
        uint256 balanceBribe1 = token1.balanceOf(bribeContract);
        assertEq(balanceLocker0, 0);
        assertEq(balanceLocker1, 0);
        assertEq(balanceOwner0, expectedOwner0);
        assertEq(balanceOwner1, expectedOwner1);
        assertEq(balanceBeneficiary0, expectedBeneficiary0);
        assertEq(balanceBeneficiary1, expectedBeneficiary1);
        assertEq(balanceBribe0, expectedBribe0);
        assertEq(balanceBribe1, expectedBribe1);
    }

    function test_WhenTheBribeAmountIsNotZero_____()
        external
        whenTheBeneficiaryIsNotAddressZero_
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryShareIsGreaterThanZero_
    {
        // It should claim the fees
        // It should send a share to the beneficiary
        // It should emit a {FeesClaimed} for the beneficiary
        // It should bribe the bribe amount
        // It should emit a {Bribed} event
        // It should send the remaining fees to the owner
        _mockFees({_fees0: fees0, _fees1: fees1});

        uint256 expectedBeneficiary0 = fees0 * beneficiaryShare / MAX_BPS;
        uint256 expectedBeneficiary1 = fees1 * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe0 = (fees0 - expectedBeneficiary0) * percentage / MAX_BPS;
        uint256 expectedBribe1 = (fees1 - expectedBeneficiary1) * percentage / MAX_BPS;
        uint256 expectedOwner0 = fees0 - expectedBeneficiary0 - expectedBribe0;
        uint256 expectedOwner1 = fees1 - expectedBeneficiary1 - expectedBribe1;

        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.bob, claimed0: expectedBeneficiary0, claimed1: expectedBeneficiary1});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(token0), amount: expectedBribe0});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: v2Pool, token: address(token1), amount: expectedBribe1});

        locker.bribe({_percentage: percentage});

        uint256 balanceLocker0 = token0.balanceOf(address(locker));
        uint256 balanceLocker1 = token1.balanceOf(address(locker));
        uint256 balanceOwner0 = token0.balanceOf(users.alice);
        uint256 balanceOwner1 = token1.balanceOf(users.alice);
        uint256 balanceBeneficiary0 = token0.balanceOf(users.bob);
        uint256 balanceBeneficiary1 = token1.balanceOf(users.bob);
        uint256 balanceBribe0 = token0.balanceOf(bribeContract);
        uint256 balanceBribe1 = token1.balanceOf(bribeContract);
        assertEq(balanceLocker0, 0);
        assertEq(balanceLocker1, 0);
        assertEq(balanceOwner0, expectedOwner0);
        assertEq(balanceOwner1, expectedOwner1);
        assertEq(balanceBeneficiary0, expectedBeneficiary0);
        assertEq(balanceBeneficiary1, expectedBeneficiary1);
        assertEq(balanceBribe0, expectedBribe0);
        assertEq(balanceBribe1, expectedBribe1);
    }

    function testGas_bribe()
        external
        whenTheBeneficiaryIsNotAddressZero_
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
        whenThePercentageIsSmallerOrEqualToBribeableShare
        whenTheLockerIsNotStaked
        whenTheBeneficiaryShareIsGreaterThanZero_
    {
        _mockFees({_fees0: fees0, _fees1: fees1});
        locker.bribe({_percentage: percentage});
        vm.snapshotGasLastCall("V2Locker_bribe");
    }
}
