// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract StakeIntegrationConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

    function test_WhenTheLockerIsStaked() external {
        // It should revert with {AlreadyStaked}
        vm.startPrank(users.alice);
        locker.stake();
        assertTrue(locker.staked());

        vm.expectRevert(ILocker.AlreadyStaked.selector);
        locker.stake();
    }

    function test_WhenTheLockerIsNotStaked() external {
        // It should claim the fees
        // It should deposit in the gauge
        // It should emit a {Staked} event
        vm.startPrank(users.alice);
        assertFalse(locker.staked());
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), address(locker));

        vm.expectEmit(address(locker));
        emit ILocker.Staked();
        locker.stake();

        assertTrue(locker.staked());
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), gauge);
    }

    function test_WhenTheLockerIsNotStaked_FeesClaimFlow() external {
        (uint256 fees0, uint256 fees1) = (10 * TOKEN_1, 10 * USDC_1);

        //mock fees by sending tokens to the pool and updating the position in storage
        deal(address(token), clPool, fees0);
        deal(address(usdc), clPool, fees1);
        uint256 balanceBefore0 = token.balanceOf(address(users.alice));
        uint256 balanceBefore1 = usdc.balanceOf(address(users.alice));

        bytes32 positionKey = computeCLPositionKey(nfpManager, tickLower, tickUpper);

        // Find the base slot for positions[key] in CLPool
        uint256 baseSlot = stdstore.target(clPool).sig("positions(bytes32)").with_key(positionKey).find();

        // slot + 3: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        uint256 packed = ((fees1) << 128) | (fees0); // tokensOwed0 is lower 128
        vm.store(clPool, bytes32(baseSlot + 3), bytes32(packed));

        // Find the base slot for positions[key] in nfpm for the locker
        uint256 baseSlotLocker = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker.lp()).find();

        // slot + 4: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        packed = ((fees1) << 128) | (fees0);
        vm.store(nfpManager, bytes32(baseSlotLocker + 4), bytes32(packed));

        assertFalse(locker.staked());
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), address(locker));

        vm.startPrank(users.alice);

        vm.expectEmit(address(clPool));
        emit ICLPool.Collect({
            owner: nfpManager,
            recipient: address(locker),
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0: uint128(fees0),
            amount1: uint128(fees1)
        });
        vm.expectEmit(address(token));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: fees0});
        vm.expectEmit(address(usdc));
        emit IERC20.Transfer({from: address(locker), to: users.alice, value: fees1});
        vm.expectEmit(address(locker));
        emit ILocker.FeesClaimed({recipient: users.alice, claimed0: fees0, claimed1: fees1});
        vm.expectEmit(address(locker));
        emit ILocker.Staked();
        locker.stake();

        assertTrue(locker.staked());
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), gauge);
        assertEq(token.balanceOf(users.alice) - balanceBefore0, fees0);
        assertEq(usdc.balanceOf(users.alice) - balanceBefore1, fees1);
    }

    function testGas_stake() external {
        vm.startPrank(users.alice);

        locker.stake();
        vm.snapshotGasLastCall("CLLocker_stake");
    }
}
