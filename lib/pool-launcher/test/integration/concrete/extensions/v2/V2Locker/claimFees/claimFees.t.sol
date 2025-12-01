// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract ClaimFeesIntegrationConcreteTest is V2LockerTest {
    using stdStorage for StdStorage;

    IERC20 public token0;
    IERC20 public token1;
    uint256 public fees0;
    uint256 public fees1;
    IV2Locker public locker2; // with beneficiary

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));
        (fees0, fees1) = poolLauncherToken < tokenToPair ? (10 * TOKEN_1, 10 * USDC_1) : (10 * USDC_1, 10 * TOKEN_1);

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
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 1000, // 10%
            _bribeableShare: 0,
            _owner: users.alice
        });
        locker2 = IV2Locker(lockerAddress);
        vm.stopPrank();
    }

    function test_WhenTheLockerIsStaked() external {
        // It should revert with {LockerStaked}
        vm.startPrank(users.alice);
        locker.stake();
        vm.expectRevert(ILocker.LockerStaked.selector);
        locker.claimFees({_recipient: users.alice});
    }

    modifier whenTheLockerIsNotStaked() {
        _;
    }

    function test_WhenTheAmountOfFeesIsZero() external whenTheLockerIsNotStaked {
        // It should keep the same locker balance
        // It should keep the same user balance
        vm.startPrank(users.alice);
        uint256 token0BalanceBefore = token0.balanceOf(address(locker));
        uint256 token1BalanceBefore = token1.balanceOf(address(locker));
        uint256 userToken0BalanceBefore = token0.balanceOf(users.alice);
        uint256 userToken1BalanceBefore = token1.balanceOf(users.alice);

        vm.expectCall({callee: address(token0), data: abi.encodeWithSelector(IERC20.transfer.selector), count: 0});
        vm.expectCall({callee: address(token1), data: abi.encodeWithSelector(IERC20.transfer.selector), count: 0});
        (uint256 claimed0, uint256 claimed1) = locker.claimFees({_recipient: users.alice});

        uint256 token0BalanceAfter = token0.balanceOf(address(locker));
        uint256 token1BalanceAfter = token1.balanceOf(address(locker));
        uint256 userToken0BalanceAfter = token0.balanceOf(users.alice);
        uint256 userToken1BalanceAfter = token1.balanceOf(users.alice);

        assertEq(claimed0, 0);
        assertEq(claimed1, 0);
        assertEq(token0BalanceBefore, token0BalanceAfter);
        assertEq(token1BalanceBefore, token1BalanceAfter);
        assertEq(userToken0BalanceBefore, userToken0BalanceAfter);
        assertEq(userToken1BalanceBefore, userToken1BalanceAfter);
    }

    modifier whenTheAmountOfFeesIsGreaterThanZero() {
        //mock fees by sending tokens to the pool fees and updating claimable in storage
        address pool = v2Pool;
        address poolFees = IV2Pool(pool).poolFees();

        deal(address(token0), poolFees, fees0);
        deal(address(token1), poolFees, fees1);

        stdstore.target({_target: pool}).sig("claimable0(address)").with_key(address(locker)).checked_write(fees0 / 2);
        stdstore.target({_target: pool}).sig("claimable1(address)").with_key(address(locker)).checked_write(fees1 / 2);
        stdstore.target({_target: pool}).sig("claimable0(address)").with_key(address(locker2)).checked_write(fees0 / 2);
        stdstore.target({_target: pool}).sig("claimable1(address)").with_key(address(locker2)).checked_write(fees1 / 2);
        _;
    }

    function test_WhenTheBeneficiaryIsAddressZero()
        external
        whenTheLockerIsNotStaked
        whenTheAmountOfFeesIsGreaterThanZero
    {
        // It should claim the fees
        // It should send the fees to the recipient
        // It should emit a {FeesClaimed} for the recipient
        uint256 totalFees0 = fees0 / 2;
        uint256 totalFees1 = fees1 / 2;
        vm.startPrank(users.alice);

        vm.expectCall({
            callee: address(token0),
            data: abi.encodeCall(IERC20.transfer, (users.alice, totalFees0)),
            count: 1
        });
        vm.expectCall({
            callee: address(token1),
            data: abi.encodeCall(IERC20.transfer, (users.alice, totalFees1)),
            count: 1
        });
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.alice, claimed0: totalFees0, claimed1: totalFees1});
        (uint256 claimed0, uint256 claimed1) = locker.claimFees({_recipient: users.alice});

        assertEq(claimed0, totalFees0);
        assertEq(claimed1, totalFees1);
        assertEq(token0.balanceOf(users.alice), totalFees0);
        assertEq(token1.balanceOf(users.alice), totalFees1);
    }

    modifier whenTheBeneficiaryIsNotAddressZero() {
        locker = locker2;
        _;
    }

    function test_WhenBeneficiaryShareIsZero()
        external
        whenTheLockerIsNotStaked
        whenTheAmountOfFeesIsGreaterThanZero
        whenTheBeneficiaryIsNotAddressZero
    {
        // It should claim the fees
        // It should send the fees to the recipient
        // It should emit a {FeesClaimed} for the recipient
        address poolFees = IV2Pool(v2Pool).poolFees();
        /// @dev small amount of fees to make beneficiary share 0. beneficiaryShare is 10% -> 10% of 9 ~= 0
        fees0 = 9;
        fees1 = 9;
        deal(address(token0), poolFees, fees0);
        deal(address(token1), poolFees, fees1);
        stdstore.target({_target: v2Pool}).sig("claimable0(address)").with_key(address(locker2)).checked_write(fees0);
        stdstore.target({_target: v2Pool}).sig("claimable1(address)").with_key(address(locker2)).checked_write(fees1);

        vm.startPrank(users.alice);
        vm.expectCall({callee: address(token0), data: abi.encodeCall(IERC20.transfer, (users.alice, fees0)), count: 1});
        vm.expectCall({callee: address(token1), data: abi.encodeCall(IERC20.transfer, (users.alice, fees1)), count: 1});
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.alice, claimed0: fees0, claimed1: fees1});
        (uint256 claimed0, uint256 claimed1) = locker.claimFees({_recipient: users.alice});

        assertEq(claimed0, fees0);
        assertEq(claimed1, fees1);
        assertEq(token0.balanceOf(users.alice), fees0);
        assertEq(token1.balanceOf(users.alice), fees1);
        assertEq(token0.balanceOf(users.bob), 0);
        assertEq(token1.balanceOf(users.bob), 0);
        assertEq(token0.balanceOf(address(locker)), 0);
        assertEq(token1.balanceOf(address(locker)), 0);
    }

    function test_WhenTheBeneficiaryShareIsGreaterThanZero()
        external
        whenTheLockerIsNotStaked
        whenTheAmountOfFeesIsGreaterThanZero
        whenTheBeneficiaryIsNotAddressZero
    {
        // It should claim the fees
        // It should send a share to the beneficiary
        // It should emit a {FeesClaimed} for the beneficiary
        // It should send the fees to the recipient
        // It should emit a {FeesClaimed} for the recipient
        uint256 totalFees0 = fees0 / 2;
        uint256 totalFees1 = fees1 / 2;
        uint256 aliceFees0 = totalFees0 * 9 / 10;
        uint256 aliceFees1 = totalFees1 * 9 / 10;
        uint256 bobFees0 = totalFees0 / 10;
        uint256 bobFees1 = totalFees1 / 10;

        vm.startPrank(users.alice);
        vm.expectCall({callee: address(token0), data: abi.encodeCall(IERC20.transfer, (users.bob, bobFees0)), count: 1});
        vm.expectCall({callee: address(token1), data: abi.encodeCall(IERC20.transfer, (users.bob, bobFees1)), count: 1});
        vm.expectCall({
            callee: address(token0),
            data: abi.encodeCall(IERC20.transfer, (users.alice, aliceFees0)),
            count: 1
        });
        vm.expectCall({
            callee: address(token1),
            data: abi.encodeCall(IERC20.transfer, (users.alice, aliceFees1)),
            count: 1
        });
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.bob, claimed0: bobFees0, claimed1: bobFees1});
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.alice, claimed0: aliceFees0, claimed1: aliceFees1});

        (uint256 claimed0, uint256 claimed1) = locker.claimFees({_recipient: users.alice});

        assertEq(claimed0, aliceFees0);
        assertEq(claimed1, aliceFees1);
        assertEq(token0.balanceOf(users.alice), aliceFees0);
        assertEq(token1.balanceOf(users.alice), aliceFees1);

        assertEq(token0.balanceOf(users.bob), bobFees0);
        assertEq(token1.balanceOf(users.bob), bobFees1);

        assertEq(token0.balanceOf(address(locker)), 0);
        assertEq(token1.balanceOf(address(locker)), 0);
    }

    function testGas_claimFees()
        external
        whenTheLockerIsNotStaked
        whenTheAmountOfFeesIsGreaterThanZero
        whenTheBeneficiaryIsNotAddressZero
    {
        vm.startPrank(users.alice);

        locker.claimFees({_recipient: users.alice});
        vm.snapshotGasLastCall("V2Locker_claimFees");
    }
}
