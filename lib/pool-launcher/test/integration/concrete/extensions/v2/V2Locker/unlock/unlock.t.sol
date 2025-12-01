// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2Locker.t.sol";

contract UnlockIntegrationConcreteTest is V2LockerTest {
    using stdStorage for StdStorage;

    address public _locker;
    address public _recipient;
    uint256 _fees0;
    uint256 _fees1;
    IERC20 token0;
    IERC20 token1;

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));
        (_fees0, _fees1) = poolLauncherToken < tokenToPair ? (10 * TOKEN_1, 10 * USDC_1) : (10 * USDC_1, 10 * TOKEN_1);

        //mock fees by sending tokens to the pool fees and updating claimable in storage
        address pool = v2Pool;
        address poolFees = IV2Pool(pool).poolFees();

        deal(address(token0), poolFees, _fees0);
        deal(address(token1), poolFees, _fees1);

        stdstore.target({_target: pool}).sig("claimable0(address)").with_key(address(locker)).checked_write(_fees0);
        stdstore.target({_target: pool}).sig("claimable1(address)").with_key(address(locker)).checked_write(_fees1);
    }

    function test_WhenTheCallerIsNotTheFactory() external {
        // It should revert with {NotFactory}
        vm.prank(users.charlie);
        vm.expectRevert(ILocker.NotFactory.selector);
        locker.unlock({_recipient: users.charlie, _refundAddress: users.charlie});
    }

    modifier whenTheCallerIsTheFactory() {
        _;
    }

    function test_WhenTheLPIsStaked() external whenTheCallerIsTheFactory {
        // It should revert with "ERC721: transfer caller is not owner nor approved"
        vm.prank(users.alice);
        locker.stake();

        vm.prank(address(v2LockerFactory));
        vm.expectRevert((bytes("ERC20: transfer amount exceeds balance")));
        locker.unlock({_recipient: users.alice, _refundAddress: users.alice});
    }

    function test_WhenTheLPIsNotStaked() external whenTheCallerIsTheFactory {
        // It should claim the available fees
        // It should set the staked flag to false
        // It should set lockedUntil to zero
        // It should transfer the LP to the recipient
        // It should refund leftover token amounts
        // It should emit an {Unlocked} event
        deal(address(token), address(locker), TOKEN_1 * 1000);
        deal(address(usdc), address(locker), USDC_1 * 1000);
        /// @dev Reset Alice's balances
        deal(address(token), users.alice, 0);
        deal(address(usdc), users.alice, 0);
        uint256 lockedLP = IGauge(gauge).balanceOf(address(locker));

        vm.prank(address(v2LockerFactory));
        vm.expectEmit(address(locker));
        emit ILocker.Unlocked({recipient: users.alice, refundAddress: users.bob});
        locker.unlock({_recipient: users.alice, _refundAddress: users.bob});

        assertFalse(locker.staked());
        assertEq(locker.lockedUntil(), 0);
        assertEq(IGauge(gauge).balanceOf(address(locker)), 0);
        assertEq(IGauge(gauge).balanceOf(users.alice), lockedLP);
        assertEq(token.balanceOf(users.bob), TOKEN_1 * 1000);
        assertEq(usdc.balanceOf(users.bob), USDC_1 * 1000);
        assertEq(token.balanceOf(users.alice), _fees0);
        assertEq(usdc.balanceOf(users.alice), _fees1);
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(usdc.balanceOf(address(locker)), 0);
    }
}
