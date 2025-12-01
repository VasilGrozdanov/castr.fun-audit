// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract ClaimFeesIntegrationConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

    IERC20 public token0;
    IERC20 public token1;
    uint256 public fees0;
    uint256 public fees1;
    ICLLocker public locker2; // with beneficiary

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));
        (fees0, fees1) = poolLauncherToken < tokenToPair ? (10 * TOKEN_1, 10 * USDC_1) : (10 * USDC_1, 10 * TOKEN_1);

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
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: lp});
        address lockerAddress = clLockerFactory.lock({
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 1000, // 10%
            _bribeableShare: 0,
            _owner: users.alice
        });
        locker2 = ICLLocker(lockerAddress);
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
        //mock fees by sending tokens to the pool and updating the position in storage
        address pool = clPool;
        deal(address(token0), pool, fees0);
        deal(address(token1), pool, fees1);

        bytes32 positionKey = computeCLPositionKey(nfpManager, tickLower, tickUpper);
        (uint128 _liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128,,) =
            ICLPool(pool).positions(positionKey);

        // Find the base slot for positions[key] in CLPool
        uint256 baseSlot = stdstore.target(pool).sig("positions(bytes32)").with_key(positionKey).find();

        // slot + 3: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        uint256 packed = ((fees1) << 128) | (fees0); // tokensOwed0 is lower 128
        vm.store(pool, bytes32(baseSlot + 3), bytes32(packed));

        // Find the base slot for positions[key] in nfpm (for both lockers)
        uint256 baseSlotLocker = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker.lp()).find();
        uint256 baseSlotLocker2 = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker2.lp()).find();

        // slot + 4: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        packed = ((fees1) << 128) | (fees0);
        vm.store(nfpManager, bytes32(baseSlotLocker + 4), bytes32(packed));
        vm.store(nfpManager, bytes32(baseSlotLocker2 + 4), bytes32(packed));
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
        vm.startPrank(users.alice);

        uint256 balanceBefore0 = token0.balanceOf(users.alice);
        uint256 balanceBefore1 = token1.balanceOf(users.alice);

        vm.expectCall({callee: address(token0), data: abi.encodeCall(IERC20.transfer, (users.alice, fees0)), count: 1});
        vm.expectCall({callee: address(token1), data: abi.encodeCall(IERC20.transfer, (users.alice, fees1)), count: 1});
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.alice, claimed0: fees0, claimed1: fees1});
        (uint256 claimed0, uint256 claimed1) = locker.claimFees({_recipient: users.alice});

        assertEq(claimed0, fees0);
        assertEq(claimed1, fees1);
        assertEq(token0.balanceOf(users.alice) - balanceBefore0, fees0);
        assertEq(token1.balanceOf(users.alice) - balanceBefore1, fees1);
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
        uint256 balanceBefore0 = token0.balanceOf(users.alice);
        uint256 balanceBefore1 = token1.balanceOf(users.alice);
        /// @dev small amount of fees to make beneficiary share 0. beneficiaryShare is 10% -> 10% of 9 ~= 0
        fees0 = 9;
        fees1 = 9;
        deal(address(token0), clPool, fees0);
        deal(address(token1), clPool, fees1);
        bytes32 positionKey = computeCLPositionKey(nfpManager, tickLower, tickUpper);
        uint256 baseSlot = stdstore.target(clPool).sig("positions(bytes32)").with_key(positionKey).find();
        uint256 packed = ((fees1) << 128) | (fees0); // tokensOwed0 is lower 128
        vm.store(clPool, bytes32(baseSlot + 3), bytes32(packed));
        uint256 baseSlotLocker = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker.lp()).find();
        packed = ((fees1) << 128) | (fees0);
        vm.store(nfpManager, bytes32(baseSlotLocker + 4), bytes32(packed));

        vm.startPrank(users.alice);
        vm.expectCall({callee: address(token0), data: abi.encodeCall(IERC20.transfer, (users.alice, fees0)), count: 1});
        vm.expectCall({callee: address(token1), data: abi.encodeCall(IERC20.transfer, (users.alice, fees1)), count: 1});
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.alice, claimed0: fees0, claimed1: fees1});

        (uint256 claimed0, uint256 claimed1) = locker.claimFees({_recipient: users.alice});

        assertEq(claimed0, fees0);
        assertEq(claimed1, fees1);
        assertEq(token0.balanceOf(users.alice) - balanceBefore0, fees0);
        assertEq(token1.balanceOf(users.alice) - balanceBefore1, fees1);

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
        uint256 aliceFees0 = fees0 * 9 / 10;
        uint256 aliceFees1 = fees1 * 9 / 10;
        uint256 bobFees0 = fees0 / 10;
        uint256 bobFees1 = fees1 / 10;
        uint256 balanceBefore0 = token0.balanceOf(users.alice);
        uint256 balanceBefore1 = token1.balanceOf(users.alice);

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
        assertEq(token0.balanceOf(users.alice) - balanceBefore0, aliceFees0);
        assertEq(token1.balanceOf(users.alice) - balanceBefore1, aliceFees1);

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
        vm.snapshotGasLastCall("CLLocker_claimFees");
    }
}
