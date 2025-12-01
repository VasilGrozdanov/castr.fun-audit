// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract BribeIntegrationFuzzTest is CLLockerTest {
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

    uint16 percentage;

    address bribeContract;
    ICLLocker public locker2; // with beneficiary and bribeable share

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));

        rewardToken = IERC20(IVotingEscrow(IVoter(voter).ve()).token());
        notifyAdmin = 0xE6A41fE61E7a1996B59d508661e3f524d6A32075;

        bribeContract = IVoter(voter).gaugeToBribe(gauge);

        vm.startPrank(users.alice);
        //mint lp2
        deal(poolLauncherToken, address(users.alice), poolLauncherAmount);
        deal(tokenToPair, address(users.alice), usdcAmount);

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
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: lp});
        address lockerAddress = clLockerFactory.lock({
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare, // 10%
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
        locker2 = ICLLocker(lockerAddress);
        vm.stopPrank();
    }

    function _mockRewards(uint256 _rewardAmount) internal {
        rewardAmount = _rewardAmount;
        stdstore.target({_target: gauge}).sig("rewards(uint256)").with_key(locker.lp()).checked_write(_rewardAmount);
        deal(address(rewardToken), address(gauge), _rewardAmount);
    }

    function _mockFees(uint256 _fees0, uint256 _fees1) internal {
        (fees0, fees1) = (_fees0, _fees1);
        /// @dev deal more than needed to avoid claim fees rounding issues
        deal(address(token0), clPool, _fees0 * 2);
        deal(address(token1), clPool, _fees1 * 2);

        bytes32 positionKey = computeCLPositionKey(nfpManager, tickLower, tickUpper);
        uint256 baseSlot = stdstore.target(clPool).sig("positions(bytes32)").with_key(positionKey).find();
        uint256 packed = ((_fees1) << 128) | (_fees0);
        vm.store(clPool, bytes32(baseSlot + 3), bytes32(packed));

        uint256 baseSlotLocker = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker.lp()).find();
        vm.store(nfpManager, bytes32(baseSlotLocker + 4), bytes32(packed));
    }

    function testFuzz_WhenCallerIsNotOwner(address _caller) external {
        // It should revert with {OwnableUnauthorizedAccount}
        vm.assume(_caller != users.alice);

        vm.prank(_caller);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, _caller));
        locker.bribe({_percentage: 0});
    }

    modifier whenCallerIsOwner() {
        vm.startPrank(users.alice);
        _;
    }

    function testFuzz_WhenTheLockerIsNotLocked(uint32 _skip) external whenCallerIsOwner {
        // It should revert with {NotLocked}
        _skip = uint32(bound(_skip, lockDuration, type(uint32).max));
        skip(lockDuration);
        clLockerFactory.unlock({_locker: address(locker), _recipient: users.alice});
        vm.expectRevert(ILocker.NotLocked.selector);
        locker.bribe({_percentage: 0});
    }

    modifier whenTheLockerIsLocked() {
        _;
    }

    function testFuzz_WhenThereIsNoGaugeForThePool() external whenCallerIsOwner whenTheLockerIsLocked {}

    modifier whenThereIsAGaugeForThePool() {
        _;
    }

    function testFuzz_WhenThePercentageIsGreaterThanBribeableShare(uint16 _percentage)
        external
        whenCallerIsOwner
        whenTheLockerIsLocked
        whenThereIsAGaugeForThePool
    {
        // It should revert with {InvalidPercentage}
        // uint16 _percentage = bribeableShare + 1;
        _percentage = uint16(bound(_percentage, bribeableShare + 1, MAX_BPS));
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
        bribeableShare = 500;
        _;
    }

    function testFuzz_WhenTheBribeAmountIsZero(uint256 _rewardAmount, uint16 _percentage)
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
        _rewardAmount = bound(_rewardAmount, 1, MAX_TOKENS);
        percentage = uint16(bound(_percentage, 0, bribeableShare));
        vm.assume(_rewardAmount * percentage / MAX_BPS == 0);

        _mockRewards(_rewardAmount);

        vm.startPrank(users.alice);

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, rewardAmount);
        assertEq(balanceBribe, 0);
    }

    function testFuzz_WhenTheBribeAmountIsNotZero(uint256 _rewardAmount, uint16 _percentage)
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
        percentage = uint16(bound(_percentage, 1, bribeableShare));
        rewardAmount = bound(_rewardAmount, 1, MAX_TOKENS);
        vm.assume(rewardAmount * percentage / MAX_BPS > 0);
        _mockRewards(rewardAmount);

        uint256 expectedBribe = rewardAmount * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBribe;

        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(rewardToken), amount: expectedBribe});

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

    function testFuzz_WhenTheBribeAmountIsZero_(uint256 _rewardAmount, uint16 _percentage)
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
        /// @dev beneficiary share is 10%. reward amount lower than 10 to have beneficiary share = 0.
        rewardAmount = bound(_rewardAmount, 1, 9);
        percentage = uint16(bound(_percentage, 0, bribeableShare));
        _mockRewards(rewardAmount);
        uint256 expectedBeneficiary = rewardAmount * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe = (rewardAmount - expectedBeneficiary) * percentage / MAX_BPS;
        vm.assume(expectedBribe == 0);

        vm.startPrank(users.alice);

        locker.bribe({_percentage: percentage});

        uint256 balanceOwner = rewardToken.balanceOf(users.alice);
        uint256 balanceBeneficiary = rewardToken.balanceOf(users.bob);
        uint256 balanceBribe = rewardToken.balanceOf(bribeContract);

        assertEq(balanceOwner, rewardAmount);
        assertEq(balanceBeneficiary, 0);
        assertEq(balanceBribe, 0);
    }

    function testFuzz_WhenTheBribeAmountIsNotZero_(uint256 _rewardAmount, uint16 _percentage)
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
        /// @dev beneficiary share is 10%. reward amount lower than 10 to have beneficiary share = 0.
        rewardAmount = bound(_rewardAmount, 1, 9);
        percentage = uint16(bound(_percentage, 1, bribeableShare));
        uint256 expectedBeneficiary = rewardAmount * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe = rewardAmount * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBeneficiary - expectedBribe;
        vm.assume(expectedBribe > 0);
        _mockRewards(rewardAmount);

        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(rewardToken), amount: expectedBribe});

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

    function testFuzz_WhenTheBribeAmountIsZero__(uint256 _rewardAmount, uint16 _percentage)
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
        rewardAmount = bound(_rewardAmount, 1, MAX_TOKENS);
        percentage = uint16(bound(_percentage, 0, bribeableShare));
        uint256 expectedBeneficiary = rewardAmount * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe = (rewardAmount - expectedBeneficiary) * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBeneficiary - expectedBribe;
        vm.assume(expectedBeneficiary > 0 && expectedBribe == 0);
        _mockRewards(rewardAmount);

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

    function testFuzz_WhenTheBribeAmountIsNotZero__(uint256 _rewardAmount, uint16 _percentage)
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
        rewardAmount = bound(_rewardAmount, 1, MAX_TOKENS);
        percentage = uint16(bound(_percentage, 1, bribeableShare));
        uint256 expectedBeneficiary = rewardAmount * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe = (rewardAmount - expectedBeneficiary) * percentage / MAX_BPS;
        uint256 expectedOwner = rewardAmount - expectedBeneficiary - expectedBribe;
        _mockRewards(rewardAmount);
        vm.assume(expectedBeneficiary > 0 && expectedBribe > 0);

        vm.startPrank(users.alice);

        vm.expectEmit(address(locker));
        emit ILocker.RewardsClaimed({recipient: users.bob, claimed: expectedBeneficiary});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(rewardToken), amount: expectedBribe});

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
        bribeableShare = 500;
        _;
    }

    function testFuzz_WhenTheBribeAmountIsZero___(uint128 _fees0, uint128 _fees1, uint16 _percentage)
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
        percentage = uint16(bound(_percentage, 0, bribeableShare));
        fees0 = bound(_fees0, 1, type(uint128).max - 1);
        fees1 = bound(_fees1, 1, type(uint128).max - 1);
        vm.assume(fees0 * percentage / MAX_BPS == 0 && fees1 * percentage / MAX_BPS == 0);

        _mockFees({_fees0: fees0, _fees1: fees1});

        uint256 expectedLocker0 = 0;
        uint256 expectedLocker1 = 0;
        uint256 expectedOwner0 = token0.balanceOf(users.alice) + fees0;
        uint256 expectedOwner1 = token1.balanceOf(users.alice) + fees1;
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

    function testFuzz_WhenTheBribeAmountIsNotZero___(uint128 _fees0, uint128 _fees1, uint16 _percentage)
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

        percentage = uint16(bound(_percentage, 1, bribeableShare));
        fees0 = bound(_fees0, 5, type(uint128).max - 1);
        fees1 = bound(_fees1, 5, type(uint128).max - 1);
        vm.assume(fees0 * percentage / MAX_BPS > 0 && fees1 * percentage / MAX_BPS > 0);

        _mockFees({_fees0: fees0, _fees1: fees1});

        uint256 expectedBribe0 = fees0 * percentage / MAX_BPS;
        uint256 expectedBribe1 = fees1 * percentage / MAX_BPS;
        uint256 expectedOwner0 = token0.balanceOf(users.alice) + fees0 - expectedBribe0;
        uint256 expectedOwner1 = token1.balanceOf(users.alice) + fees1 - expectedBribe1;

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(token0), amount: expectedBribe0});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(token1), amount: expectedBribe1});

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

    function testFuzz_WhenTheBribeAmountIsZero____(uint128 _fees0, uint128 _fees1, uint16 _percentage)
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
        /// @dev beneficiary share is 10%. fees lower than 10 to have beneficiary share = 0.
        fees0 = bound(_fees0, 1, 9);
        fees1 = bound(_fees1, 1, 9);
        percentage = uint16(bound(_percentage, 0, bribeableShare));
        uint256 expectedBeneficiary0 = fees0 * beneficiaryShare / MAX_BPS;
        uint256 expectedBeneficiary1 = fees1 * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe0 = fees0 * percentage / MAX_BPS;
        uint256 expectedBribe1 = fees1 * percentage / MAX_BPS;
        uint256 expectedOwner0 = token0.balanceOf(users.alice) + fees0;
        uint256 expectedOwner1 = token1.balanceOf(users.alice) + fees1;
        vm.assume(expectedBribe0 == 0 && expectedBribe1 == 0);
        _mockFees({_fees0: fees0, _fees1: fees1});

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

    function testFuzz_WhenTheBribeAmountIsNotZero____(uint128 _fees0, uint128 _fees1, uint16 _percentage)
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
        /// @dev beneficiary share is 10%. fees lower than 10 to have beneficiary share = 0.
        fees0 = bound(_fees0, 1, 9);
        fees1 = bound(_fees1, 1, 9);
        percentage = uint16(bound(_percentage, beneficiaryShare + 1, bribeableShare));
        uint256 expectedBeneficiary0 = fees0 * beneficiaryShare / MAX_BPS;
        uint256 expectedBeneficiary1 = fees1 * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe0 = fees0 * percentage / MAX_BPS;
        uint256 expectedBribe1 = fees1 * percentage / MAX_BPS;
        uint256 expectedOwner0 = token0.balanceOf(users.alice) + fees0 - expectedBribe0;
        uint256 expectedOwner1 = token1.balanceOf(users.alice) + fees1 - expectedBribe1;
        vm.assume(expectedBribe0 > 0 && expectedBribe1 > 0);

        _mockFees({_fees0: fees0, _fees1: fees1});

        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(token0), amount: expectedBribe0});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(token1), amount: expectedBribe1});

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

    function testFuzz_WhenTheBribeAmountIsZero_____(uint128 _fees0, uint128 _fees1, uint16 _percentage)
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
        /// @dev beneficiary share is 10%. fees greater than 9 to have beneficiary share > 0.
        fees0 = bound(_fees0, 10, type(uint128).max - 1);
        fees1 = bound(_fees1, 10, type(uint128).max - 1);
        percentage = uint16(bound(_percentage, 0, bribeableShare));

        uint256 expectedBeneficiary0 = fees0 * beneficiaryShare / MAX_BPS;
        uint256 expectedBeneficiary1 = fees1 * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe0 = (fees0 - expectedBeneficiary0) * percentage / MAX_BPS;
        uint256 expectedBribe1 = (fees1 - expectedBeneficiary1) * percentage / MAX_BPS;
        uint256 expectedOwner0 = token0.balanceOf(users.alice) + fees0 - expectedBeneficiary0 - expectedBribe0;
        uint256 expectedOwner1 = token1.balanceOf(users.alice) + fees1 - expectedBeneficiary1 - expectedBribe1;

        vm.assume(expectedBeneficiary0 > 0 && expectedBeneficiary1 > 0 && expectedBribe0 == 0 && expectedBribe1 == 0);

        _mockFees({_fees0: fees0, _fees1: fees1});

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

    function testFuzz_WhenTheBribeAmountIsNotZero_____(uint128 _fees0, uint128 _fees1, uint16 _percentage)
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
        /// @dev beneficiary share is 10%. fees greater than 9 to have beneficiary share = 0.
        fees0 = bound(_fees0, 10, type(uint128).max - 1);
        fees1 = bound(_fees1, 10, type(uint128).max - 1);
        percentage = uint16(bound(_percentage, 1, bribeableShare));
        uint256 expectedBeneficiary0 = fees0 * beneficiaryShare / MAX_BPS;
        uint256 expectedBeneficiary1 = fees1 * beneficiaryShare / MAX_BPS;
        uint256 expectedBribe0 = (fees0 - expectedBeneficiary0) * percentage / MAX_BPS;
        uint256 expectedBribe1 = (fees1 - expectedBeneficiary1) * percentage / MAX_BPS;
        uint256 expectedOwner0 = token0.balanceOf(users.alice) + fees0 - expectedBeneficiary0 - expectedBribe0;
        uint256 expectedOwner1 = token1.balanceOf(users.alice) + fees1 - expectedBeneficiary1 - expectedBribe1;
        vm.assume(expectedBeneficiary0 > 0 && expectedBeneficiary1 > 0 && expectedBribe0 > 0 && expectedBribe1 > 0);

        _mockFees({_fees0: fees0, _fees1: fees1});

        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.bob, claimed0: expectedBeneficiary0, claimed1: expectedBeneficiary1});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(token0), amount: expectedBribe0});
        vm.expectEmit(address(locker));
        emit ILocker.Bribed({pool: clPool, token: address(token1), amount: expectedBribe1});

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
}
