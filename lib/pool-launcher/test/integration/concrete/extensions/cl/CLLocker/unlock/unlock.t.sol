// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract UnlockIntegrationConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

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

        //mock fees by sending tokens to the pool and updating the position in storage
        deal(address(token0), clPool, _fees0);
        deal(address(token1), clPool, _fees1);

        bytes32 positionKey = computeCLPositionKey(nfpManager, tickLower, tickUpper);

        // Find the base slot for positions[key] in CLclPool
        uint256 baseSlot = stdstore.target(clPool).sig("positions(bytes32)").with_key(positionKey).find();

        // slot + 3: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        uint256 packed = ((_fees1) << 128) | (_fees0); // tokensOwed0 is lower 128
        vm.store(clPool, bytes32(baseSlot + 3), bytes32(packed));

        // Find the base slot for positions[key] in nfpm (for both lockers)
        uint256 baseSlotLocker = stdstore.target(nfpManager).sig("positions(uint256)").with_key(locker.lp()).find();

        // slot + 4: tokensOwed0 (low 128) | tokensOwed1 (high 128)
        packed = ((_fees1) << 128) | (_fees0);
        vm.store(nfpManager, bytes32(baseSlotLocker + 4), bytes32(packed));
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
        // It should revert "EvmError: Revert"
        // Reverts inside the nfpm while trying to claim fees before unlocking.
        vm.prank(users.alice);
        locker.stake();

        vm.prank(address(clLockerFactory));
        vm.expectRevert({revertData: bytes(""), reverter: address(nfpManager)});
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

        vm.prank(address(clLockerFactory));
        vm.expectEmit(address(locker));
        emit ILocker.Unlocked({recipient: users.alice, refundAddress: users.bob});
        locker.unlock({_recipient: users.alice, _refundAddress: users.bob});

        assertFalse(locker.staked());
        assertEq(locker.lockedUntil(), 0);
        assertEq(INfpm(nfpManager).ownerOf(locker.lp()), users.alice);
        assertEq(token.balanceOf(users.bob), TOKEN_1 * 1000);
        assertEq(usdc.balanceOf(users.bob), USDC_1 * 1000);
        assertEq(token.balanceOf(users.alice), _fees0);
        assertEq(usdc.balanceOf(users.alice), _fees1);
        assertEq(token.balanceOf(address(locker)), 0);
        assertEq(usdc.balanceOf(address(locker)), 0);
    }
}
