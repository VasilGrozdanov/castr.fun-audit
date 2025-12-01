// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLocker.t.sol";

contract InitializeUnitConcreteTest is CLLockerTest {
    using stdStorage for StdStorage;

    function test_WhenTheLockerIsTheImplementation() external {
        // It should revert with {NotLocker}
        locker = CLLocker(deployCL.clLockerImplementation());

        vm.expectRevert(ILockerFactory.NotLocker.selector);
        locker.initialize({
            _owner: users.alice,
            _pool: clPool,
            _lp: lp,
            _lockedUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 1_000,
            _bribeableShare: 500
        });
    }

    modifier whenTheLockerIsNotTheImplementation() {
        locker = new CLLocker({_factory: address(clLockerFactory), _root: false});

        assertEq(Ownable(address(locker)).owner(), address(clLockerFactory));
        assertEq(address(locker.nfpManager()), nfpManager);
        assertEq(locker.MAX_BPS(), MAX_BPS);
        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(clLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertFalse(locker.root());
        assertFalse(locker.staked());
        _;
    }

    function test_WhenTheLockerHasAlreadyBeenInitialized() external whenTheLockerIsNotTheImplementation {
        // It should revert with {InvalidInitialization}
        stdstore.target({_target: address(clLockerFactory)}).sig("instances(address)").with_key(address(locker))
            .checked_write(true);
        locker.initialize({
            _owner: users.alice,
            _pool: clPool,
            _lp: lp,
            _lockedUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 1_000,
            _bribeableShare: 500
        });

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        locker.initialize({
            _owner: users.alice,
            _pool: clPool,
            _lp: lp,
            _lockedUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 1_000,
            _bribeableShare: 500
        });
    }

    function test_WhenTheLockerHasNotBeenInitialized() external whenTheLockerIsNotTheImplementation {
        // It should initialize the locker state
        // It should set the locker owner
        stdstore.target({_target: address(clLockerFactory)}).sig("instances(address)").with_key(address(locker))
            .checked_write(true);
        locker.initialize({
            _owner: users.alice,
            _pool: clPool,
            _lp: lp,
            _lockedUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 1_000,
            _bribeableShare: 500
        });

        assertEq(Ownable(address(locker)).owner(), users.alice);
        assertEq(address(locker.nfpManager()), nfpManager);
        assertEq(locker.MAX_BPS(), MAX_BPS);
        assertEq(address(locker.voter()), voter);
        assertEq(locker.factory(), address(clLockerFactory));
        assertEq(uint8(locker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));
        assertEq(locker.pool(), clPool);
        assertEq(locker.token0(), address(token));
        assertEq(locker.token1(), address(usdc));
        assertEq(locker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(locker.lp(), lp);
        assertEq(locker.beneficiary(), users.bob);
        assertEq(locker.beneficiaryShare(), 1_000);
        assertFalse(locker.root());
        assertEq(address(locker.gauge()), address(0));
        assertEq(locker.bribeableShare(), 500);
        assertEq(locker.lockedUntil(), block.timestamp + lockDuration);
        assertFalse(locker.staked());
    }
}
