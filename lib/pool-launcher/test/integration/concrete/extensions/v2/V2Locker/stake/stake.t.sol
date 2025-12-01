// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract StakeIntegrationConcreteTest is V2LockerTest {
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
        assertEq(IGauge(gauge).balanceOf(address(locker)), 0);

        vm.expectEmit(address(locker));
        emit ILocker.Staked();
        locker.stake();

        assertTrue(locker.staked());
        assertEq(IGauge(gauge).balanceOf(address(locker)), locker.lp());
    }

    function test_WhenTheLockerIsNotStaked_FeesClaimFlow() external {
        address poolFees = IV2Pool(v2Pool).poolFees();
        (uint256 fees0, uint256 fees1) = (10 * TOKEN_1, 10 * USDC_1);
        deal(address(token), poolFees, fees0);
        deal(address(usdc), poolFees, fees1);

        stdstore.target({_target: v2Pool}).sig("claimable0(address)").with_key(address(locker)).checked_write(fees0);
        stdstore.target({_target: v2Pool}).sig("claimable1(address)").with_key(address(locker)).checked_write(fees1);

        vm.startPrank(users.alice);
        assertFalse(locker.staked());
        assertEq(IGauge(gauge).balanceOf(address(locker)), 0);

        vm.expectEmit(address(v2Pool));
        emit IV2Pool.Claim({sender: address(locker), recipient: address(locker), amount0: fees0, amount1: fees1});
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
        assertEq(IGauge(gauge).balanceOf(address(locker)), locker.lp());
        assertEq(token.balanceOf(users.alice), fees0);
        assertEq(usdc.balanceOf(users.alice), fees1);
    }

    function testGas_stake() external {
        vm.startPrank(users.alice);

        locker.stake();
        vm.snapshotGasLastCall("V2Locker_stake");
    }
}
