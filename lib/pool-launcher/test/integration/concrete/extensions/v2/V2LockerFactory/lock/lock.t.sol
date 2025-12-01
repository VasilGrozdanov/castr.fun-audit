// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../V2LockerFactory.t.sol";

contract LockIntegrationConcreteTest is V2LockerFactoryTest {
    IERC20 public token0;
    IERC20 public token1;

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));

        vm.startPrank(users.alice);
        //mint lp2
        deal(poolLauncherToken, v2Pool, poolLauncherAmount * 4);
        deal(tokenToPair, v2Pool, usdcAmount * 4);
        lp = IV2Pool(v2Pool).mint({to: users.alice});
        vm.stopPrank();
    }

    function test_WhenTheLockUntilIsLowerOrEqualToTimestamp() external {
        // It should revert with {InvalidLockTime}
        vm.expectRevert(ILockerFactory.InvalidLockTime.selector);
        v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp - 1),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 0,
            _owner: users.alice
        });
    }

    modifier whenTheLockUntilIsGreaterThanTimestamp() {
        _;
    }

    modifier whenTheBeneficiaryIsNotAddressZero() {
        _;
    }

    function test_WhenTheBeneficiaryShareIsZeroOrGreaterThanMAX_BPS()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
    {
        // It should revert with {InvalidBeneficiaryShare}
        vm.expectRevert(ILockerFactory.InvalidBeneficiaryShare.selector);
        v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 0,
            _bribeableShare: 0,
            _owner: users.alice
        });

        uint16 beneficiaryShare = uint16(v2LockerFactory.MAX_BPS() + 1);
        vm.expectRevert(ILockerFactory.InvalidBeneficiaryShare.selector);
        v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare,
            _bribeableShare: 0,
            _owner: users.alice
        });
    }

    modifier whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS() {
        _;
    }

    function test_WhenTheBribeableShareIsGreaterThanMAX_BPS()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
    {
        // It should revert with {InvalidBribeableShare}
        uint16 beneficiaryShare = uint16(v2LockerFactory.MAX_BPS());
        uint16 bribeableShare = uint16(v2LockerFactory.MAX_BPS() + 1);
        vm.expectRevert(ILockerFactory.InvalidBribeableShare.selector);
        v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: beneficiaryShare,
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
    }

    modifier whenTheBribeableShareIsSmallerOrEqualToMAX_BPS() {
        _;
    }

    function test_WhenThePoolIsNotInThePoolFactory()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
    {
        // It should revert with {PoolNotInFactory}
        address pool = makeAddr("pool");
        vm.expectRevert(IV2LockerFactory.PoolNotInFactory.selector);
        v2LockerFactory.lock({
            _pool: pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: uint16(MAX_BPS),
            _bribeableShare: uint16(MAX_BPS),
            _owner: users.alice
        });
    }

    modifier whenThePoolIsInThePoolFactory() {
        _;
    }

    function test_WhenTheCallerIsNotThePoolLauncher()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
        whenThePoolIsInThePoolFactory
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It should pull the liquidity from the user to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = v2LockerFactory.locked(v2Pool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 2});

        vm.startPrank(users.alice);
        IERC20(v2Pool).approve({spender: address(v2LockerFactory), value: lp});
        vm.expectEmit(address(v2Pool));
        emit IERC20.Transfer({from: users.alice, to: predictedLocker, value: lp});
        vm.expectEmit(address(v2LockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: uint16(v2LockerFactory.MAX_BPS()),
            bribeableShare: 1000
        });
        address newLocker = v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: uint16(v2LockerFactory.MAX_BPS()),
            _bribeableShare: 1000,
            _owner: users.alice
        });

        assertTrue(v2LockerFactory.instances(address(locker)));
        assertTrue(v2LockerFactory.instances(address(newLocker)));
        assertEq(v2LockerFactory.locked(v2Pool), liquidityBefore + lp);
        assertEq(v2LockerFactory.locked(v2Pool, 0, 2), liquidityBefore + lp);
        assertEq(v2LockerFactory.locks(v2Pool), 2);

        // @dev assert lockers mapping and view functions
        address[] memory lockers = v2LockerFactory.lockers(v2Pool);
        assertEq(lockers.length, 2);
        assertEq(lockers[0], address(locker));
        assertEq(lockers[1], newLocker);
        lockers = v2LockerFactory.lockers(v2Pool, 0, 2);
        assertEq(lockers.length, 2);
        assertEq(lockers[0], address(locker));
        assertEq(lockers[1], newLocker);
        assertEq(v2LockerFactory.lockersCount(v2Pool), 2);

        // @dev assert lockersPerUser mapping and view functions
        address[] memory lockersPerUser = v2LockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, 2);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(lockersPerUser[1], newLocker);
        lockersPerUser = v2LockerFactory.lockersPerUser(users.alice, 0, 2);
        assertEq(lockersPerUser.length, 2);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(lockersPerUser[1], newLocker);
        assertEq(v2LockerFactory.lockersPerUserCount(users.alice), 2);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        address[] memory lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice);
        assertEq(lockersPerPoolPerUser.length, 2);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(lockersPerPoolPerUser[1], newLocker);
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice, 0, 2);
        assertEq(lockersPerPoolPerUser.length, 2);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(lockersPerPoolPerUser[1], newLocker);
        assertEq(v2LockerFactory.lockersPerPoolPerUserCount(v2Pool, users.alice), 2);

        assertEq(IV2Pool(v2Pool).balanceOf(address(newLocker)), IV2Locker(newLocker).lp());
        assertEq(IV2Pool(v2Pool).balanceOf(users.alice), 0);
        assertEq(IERC20(v2Pool).allowance(users.alice, address(v2LockerFactory)), 0);
    }

    function test_WhenTheCallerIsThePoolLauncher()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
        whenThePoolIsInThePoolFactory
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It should transfer the liquidity to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = v2LockerFactory.locked(v2Pool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 2});

        vm.prank(users.alice);
        IERC20(v2Pool).transfer({to: address(v2LockerFactory), value: lp});

        vm.startPrank(address(v2PoolLauncher));
        vm.expectEmit(address(v2Pool));
        emit IERC20.Transfer({from: address(v2LockerFactory), to: predictedLocker, value: lp});
        vm.expectEmit(address(v2LockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: uint16(v2LockerFactory.MAX_BPS()),
            bribeableShare: 1000
        });
        address newLocker = v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: uint16(v2LockerFactory.MAX_BPS()),
            _bribeableShare: 1000,
            _owner: users.alice
        });

        assertTrue(v2LockerFactory.instances(address(locker)));
        assertTrue(v2LockerFactory.instances(address(newLocker)));
        assertEq(v2LockerFactory.locked(v2Pool), liquidityBefore + lp);
        assertEq(v2LockerFactory.locked(v2Pool, 0, 2), liquidityBefore + lp);
        assertEq(v2LockerFactory.locks(v2Pool), 2);

        // @dev assert lockers mapping and view functions
        address[] memory lockers = v2LockerFactory.lockers(v2Pool);
        assertEq(lockers.length, 2);
        assertEq(lockers[0], address(locker));
        assertEq(lockers[1], newLocker);
        lockers = v2LockerFactory.lockers(v2Pool, 0, 2);
        assertEq(lockers.length, 2);
        assertEq(lockers[0], address(locker));
        assertEq(lockers[1], newLocker);
        assertEq(v2LockerFactory.lockersCount(v2Pool), 2);

        // @dev assert lockersPerUser mapping and view functions
        address[] memory lockersPerUser = v2LockerFactory.lockersPerUser(users.alice);
        assertEq(lockersPerUser.length, 2);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(lockersPerUser[1], newLocker);
        lockersPerUser = v2LockerFactory.lockersPerUser(users.alice, 0, 2);
        assertEq(lockersPerUser.length, 2);
        assertEq(lockersPerUser[0], address(locker));
        assertEq(lockersPerUser[1], newLocker);
        assertEq(v2LockerFactory.lockersPerUserCount(users.alice), 2);

        // @dev assert lockersPerPoolPerUser mapping and view functions
        address[] memory lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice);
        assertEq(lockersPerPoolPerUser.length, 2);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(lockersPerPoolPerUser[1], newLocker);
        lockersPerPoolPerUser = v2LockerFactory.lockersPerPoolPerUser(v2Pool, users.alice, 0, 2);
        assertEq(lockersPerPoolPerUser.length, 2);
        assertEq(lockersPerPoolPerUser[0], address(locker));
        assertEq(lockersPerPoolPerUser[1], newLocker);
        assertEq(v2LockerFactory.lockersPerPoolPerUserCount(v2Pool, users.alice), 2);

        assertEq(IV2Pool(v2Pool).balanceOf(address(newLocker)), IV2Locker(newLocker).lp());
        assertEq(IV2Pool(v2Pool).balanceOf(users.alice), 0);
        assertEq(IERC20(v2Pool).allowance(users.alice, address(v2LockerFactory)), 0);
    }

    modifier whenTheBeneficiaryIsAddressZero() {
        _;
    }

    function test_WhenTheBribeableShareIsGreaterThanMAX_BPS_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
    {
        // It should revert with {InvalidBribeableShare}
        uint16 bribeableShare = uint16(v2LockerFactory.MAX_BPS() + 1);
        vm.expectRevert(ILockerFactory.InvalidBribeableShare.selector);
        v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: bribeableShare,
            _owner: users.alice
        });
    }

    modifier whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_() {
        _;
    }

    function test_WhenThePoolIsNotInThePoolFactory_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_
    {
        // It should revert with {PoolNotInFactory}
        address pool = makeAddr("pool");
        vm.expectRevert(IV2LockerFactory.PoolNotInFactory.selector);
        v2LockerFactory.lock({
            _pool: pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 1000,
            _owner: users.alice
        });
    }

    modifier whenThePoolIsInThePoolFactory_() {
        _;
    }

    function test_WhenTheCallerIsNotThePoolLauncher_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_
        whenThePoolIsInThePoolFactory_
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It should pull the liquidity from the user to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = v2LockerFactory.locked(v2Pool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 2});

        vm.startPrank(users.alice);
        IERC20(v2Pool).approve({spender: address(v2LockerFactory), value: lp});
        vm.expectEmit(address(v2Pool));
        emit IERC20.Transfer({from: users.alice, to: predictedLocker, value: lp});
        vm.expectEmit(address(v2LockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: 500,
            bribeableShare: 1000
        });
        IV2Locker newLocker = IV2Locker(
            v2LockerFactory.lock({
                _pool: v2Pool,
                _lp: lp,
                _lockUntil: uint32(block.timestamp + lockDuration),
                _beneficiary: users.bob,
                _beneficiaryShare: 500,
                _bribeableShare: 1000,
                _owner: users.alice
            })
        );

        assertTrue(v2LockerFactory.instances(address(locker)));
        assertTrue(v2LockerFactory.instances(address(newLocker)));
        assertEq(v2LockerFactory.locked(v2Pool), liquidityBefore + lp);
        assertEq(v2LockerFactory.locked(v2Pool, 0, 2), liquidityBefore + lp);
        assertEq(v2LockerFactory.locks(v2Pool), 2);

        _assertMappings(2, address(newLocker), address(0));

        assertEq(Ownable(address(newLocker)).owner(), users.alice);
        assertEq(newLocker.router(), v2Router);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(v2LockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.BASIC));

        assertEq(newLocker.pool(), v2Pool);
        assertEq(newLocker.token0(), address(token));
        assertEq(newLocker.token1(), address(usdc));
        assertEq(newLocker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(newLocker.beneficiary(), users.bob);
        assertEq(newLocker.beneficiaryShare(), 500);
        assertFalse(newLocker.root());

        assertEq(address(newLocker.gauge()), address(0));
        assertEq(newLocker.bribeableShare(), 1000);
        assertEq(newLocker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(newLocker.staked());

        assertEq(IV2Pool(v2Pool).balanceOf(address(newLocker)), newLocker.lp());
        assertEq(IV2Pool(v2Pool).balanceOf(users.alice), 0);
        assertEq(IERC20(v2Pool).allowance(users.alice, address(v2LockerFactory)), 0);
    }

    function test_WhenTheCallerIsThePoolLauncher_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_
        whenThePoolIsInThePoolFactory_
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It should transfer the liquidity to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = v2LockerFactory.locked(v2Pool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(v2LockerFactory), nonce: 2});

        vm.prank(users.alice);
        IERC20(v2Pool).transfer({to: address(v2LockerFactory), value: lp});

        vm.startPrank(address(v2PoolLauncher));
        vm.expectEmit(address(v2Pool));
        emit IERC20.Transfer({from: address(v2LockerFactory), to: predictedLocker, value: lp});
        vm.expectEmit(address(v2LockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: 500,
            bribeableShare: 1000
        });
        IV2Locker newLocker = IV2Locker(
            v2LockerFactory.lock({
                _pool: v2Pool,
                _lp: lp,
                _lockUntil: uint32(block.timestamp + lockDuration),
                _beneficiary: users.bob,
                _beneficiaryShare: 500,
                _bribeableShare: 1000,
                _owner: users.alice
            })
        );

        assertTrue(v2LockerFactory.instances(address(locker)));
        assertTrue(v2LockerFactory.instances(address(newLocker)));
        assertEq(v2LockerFactory.locked(v2Pool), liquidityBefore + lp);
        assertEq(v2LockerFactory.locked(v2Pool, 0, 2), liquidityBefore + lp);
        assertEq(v2LockerFactory.locks(v2Pool), 2);

        _assertMappings(2, address(newLocker), address(0));

        assertEq(Ownable(address(newLocker)).owner(), users.alice);
        assertEq(newLocker.router(), v2Router);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(v2LockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.BASIC));

        assertEq(newLocker.pool(), v2Pool);
        assertEq(newLocker.token0(), address(token));
        assertEq(newLocker.token1(), address(usdc));
        assertEq(newLocker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(newLocker.beneficiary(), users.bob);
        assertEq(newLocker.beneficiaryShare(), 500);
        assertFalse(newLocker.root());

        assertEq(address(newLocker.gauge()), address(0));
        assertEq(newLocker.bribeableShare(), 1000);
        assertEq(newLocker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(newLocker.staked());

        assertEq(IV2Pool(v2Pool).balanceOf(address(newLocker)), newLocker.lp());
        assertEq(IV2Pool(v2Pool).balanceOf(users.alice), 0);
        assertEq(IERC20(v2Pool).allowance(users.alice, address(v2LockerFactory)), 0);
    }

    function testGas_lock()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
        whenThePoolIsInThePoolFactory
    {
        vm.startPrank(users.alice);
        IERC20(v2Pool).approve({spender: address(v2LockerFactory), value: lp});
        v2LockerFactory.lock({
            _pool: v2Pool,
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 1000,
            _owner: users.alice
        });
        vm.snapshotGasLastCall("V2LockerFactory_lock");
    }
}
