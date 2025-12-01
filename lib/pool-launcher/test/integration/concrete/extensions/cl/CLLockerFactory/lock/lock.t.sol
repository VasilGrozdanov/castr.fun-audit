// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../CLLockerFactory.t.sol";

contract LockIntegrationConcreteTest is CLLockerFactoryTest {
    IERC20 public token0;
    IERC20 public token1;

    function setUp() public override {
        super.setUp();

        (token0, token1) = poolLauncherToken < tokenToPair
            ? (IERC20(poolLauncherToken), IERC20(tokenToPair))
            : (IERC20(tokenToPair), IERC20(poolLauncherToken));

        //mint lp2
        deal(poolLauncherToken, address(users.alice), poolLauncherAmount);
        deal(tokenToPair, address(users.alice), usdcAmount);

        vm.startPrank(users.alice);
        lp = mintLP({
            token0: poolLauncherToken < tokenToPair ? poolLauncherToken : tokenToPair,
            token1: poolLauncherToken < tokenToPair ? tokenToPair : poolLauncherToken,
            tickSpacing: TICK_SPACING_200,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0: poolLauncherToken < tokenToPair ? poolLauncherAmount : usdcAmount,
            amount1: poolLauncherToken < tokenToPair ? usdcAmount : poolLauncherAmount,
            recipient: users.alice
        });
        vm.stopPrank();
    }

    function test_WhenTheLockUntilIsLowerOrEqualToTimestamp() external {
        // It should revert with {InvalidLockTime}
        vm.expectRevert(ILockerFactory.InvalidLockTime.selector);
        clLockerFactory.lock({
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
        clLockerFactory.lock({
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: 0,
            _bribeableShare: 0,
            _owner: users.alice
        });

        uint16 beneficiaryShare = uint16(clLockerFactory.MAX_BPS() + 1);
        vm.expectRevert(ILockerFactory.InvalidBeneficiaryShare.selector);
        clLockerFactory.lock({
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
        uint16 beneficiaryShare = uint16(clLockerFactory.MAX_BPS());
        uint16 bribeableShare = uint16(clLockerFactory.MAX_BPS() + 1);
        vm.expectRevert(ILockerFactory.InvalidBribeableShare.selector);
        clLockerFactory.lock({
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

    function test_WhenThePositionToLockDoesNotExistInTheNfpm()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
    {
        // It should revert with {ID}
        uint256 invalidLp = 999999;
        uint16 maxBps = uint16(clLockerFactory.MAX_BPS());
        vm.expectRevert(bytes("ID"));
        clLockerFactory.lock({
            _lp: invalidLp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: users.bob,
            _beneficiaryShare: maxBps,
            _bribeableShare: 1000,
            _owner: users.alice
        });
    }

    modifier whenThePositionToLockExistsInTheNfpm() {
        _;
    }

    function test_WhenTheCallerIsNotThePoolLauncher()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
        whenThePositionToLockExistsInTheNfpm
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It should pull the LP from the user to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = clLockerFactory.locked(clPool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(clLockerFactory), nonce: 2});

        vm.startPrank(users.alice);
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: lp});
        vm.expectCall(nfpManager, abi.encodeCall(INfpm.safeTransferFrom, (users.alice, predictedLocker, lp)));
        vm.expectEmit(address(clLockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: uint16(clLockerFactory.MAX_BPS()),
            bribeableShare: 1000
        });
        ICLLocker newLocker = ICLLocker(
            clLockerFactory.lock({
                _lp: lp,
                _lockUntil: uint32(block.timestamp + lockDuration),
                _beneficiary: users.bob,
                _beneficiaryShare: uint16(clLockerFactory.MAX_BPS()),
                _bribeableShare: 1000,
                _owner: users.alice
            })
        );

        (,,,,,,, uint128 liquidity,,,,) = INfpm(nfpManager).positions({tokenId: lp});

        assertTrue(clLockerFactory.instances(address(locker)));
        assertTrue(clLockerFactory.instances(address(newLocker)));
        assertEq(clLockerFactory.locked(clPool), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locked(clPool, 0, 2), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locks(clPool), 2);

        _assertMappings(2, address(newLocker), address(0));

        assertEq(Ownable(address(newLocker)).owner(), users.alice);
        assertEq(address(newLocker.nfpManager()), nfpManager);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(clLockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(newLocker.pool(), clPool);
        assertEq(newLocker.token0(), address(token));
        assertEq(newLocker.token1(), address(usdc));
        assertEq(newLocker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(newLocker.beneficiary(), users.bob);
        assertEq(newLocker.beneficiaryShare(), MAX_BPS);
        assertFalse(newLocker.root());

        assertEq(address(newLocker.gauge()), address(0));
        assertEq(newLocker.bribeableShare(), 1000);
        assertEq(newLocker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(newLocker.staked());

        assertEq(INfpm(nfpManager).ownerOf(newLocker.lp()), address(newLocker));
    }

    function test_WhenTheCallerIsThePoolLauncher()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsNotAddressZero
        whenTheBeneficiaryShareIsNotZeroNorGreaterThanMAX_BPS
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
        whenThePositionToLockExistsInTheNfpm
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It shoult transfer the LP to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = clLockerFactory.locked(clPool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(clLockerFactory), nonce: 2});

        vm.prank(users.alice);
        INfpm(nfpManager).safeTransferFrom({from: users.alice, to: address(clLockerFactory), tokenId: lp});

        vm.startPrank(address(clPoolLauncher));
        vm.expectCall(
            nfpManager, abi.encodeCall(INfpm.safeTransferFrom, (address(clLockerFactory), predictedLocker, lp))
        );
        vm.expectEmit(address(clLockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: uint16(clLockerFactory.MAX_BPS()),
            bribeableShare: 1000
        });
        ICLLocker newLocker = ICLLocker(
            clLockerFactory.lock({
                _lp: lp,
                _lockUntil: uint32(block.timestamp + lockDuration),
                _beneficiary: users.bob,
                _beneficiaryShare: uint16(clLockerFactory.MAX_BPS()),
                _bribeableShare: 1000,
                _owner: users.alice
            })
        );

        (,,,,,,, uint128 liquidity,,,,) = INfpm(nfpManager).positions({tokenId: lp});

        assertTrue(clLockerFactory.instances(address(locker)));
        assertTrue(clLockerFactory.instances(address(newLocker)));
        assertEq(clLockerFactory.locked(clPool), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locked(clPool, 0, 2), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locks(clPool), 2);

        _assertMappings(2, address(newLocker), address(0));

        assertEq(Ownable(address(newLocker)).owner(), users.alice);
        assertEq(address(newLocker.nfpManager()), nfpManager);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(clLockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(newLocker.pool(), clPool);
        assertEq(newLocker.token0(), address(token));
        assertEq(newLocker.token1(), address(usdc));
        assertEq(newLocker.rewardToken(), IVotingEscrow(IVoter(voter).ve()).token());
        assertEq(newLocker.beneficiary(), users.bob);
        assertEq(newLocker.beneficiaryShare(), MAX_BPS);
        assertFalse(newLocker.root());

        assertEq(address(newLocker.gauge()), address(0));
        assertEq(newLocker.bribeableShare(), 1000);
        assertEq(newLocker.lockedUntil(), uint32(block.timestamp + lockDuration));
        assertFalse(newLocker.staked());

        assertEq(INfpm(nfpManager).ownerOf(newLocker.lp()), address(newLocker));
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
        uint16 bribeableShare = uint16(clLockerFactory.MAX_BPS() + 1);
        vm.expectRevert(ILockerFactory.InvalidBribeableShare.selector);
        clLockerFactory.lock({
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

    function test_WhenThePositionToLockDoesNotExistInTheNfpm_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_
    {
        // It should revert with {ID}
        uint256 invalidLp = 999999;
        vm.expectRevert(bytes("ID"));
        clLockerFactory.lock({
            _lp: invalidLp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 1000,
            _owner: users.alice
        });
    }

    modifier whenThePositionToLockExistsInTheNfpm_() {
        _;
    }

    function test_WhenTheCallerIsNotThePoolLauncher_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_
        whenThePositionToLockExistsInTheNfpm_
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It should pull the LP from the user to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = clLockerFactory.locked(clPool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(clLockerFactory), nonce: 2});

        vm.startPrank(users.alice);
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: lp});
        vm.expectCall(nfpManager, abi.encodeCall(INfpm.safeTransferFrom, (users.alice, predictedLocker, lp)));
        vm.expectEmit(address(clLockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: 500,
            bribeableShare: 1000
        });
        ICLLocker newLocker = ICLLocker(
            clLockerFactory.lock({
                _lp: lp,
                _lockUntil: uint32(block.timestamp + lockDuration),
                _beneficiary: users.bob,
                _beneficiaryShare: 500,
                _bribeableShare: 1000,
                _owner: users.alice
            })
        );

        (,,,,,,, uint128 liquidity,,,,) = INfpm(nfpManager).positions({tokenId: lp});

        assertTrue(clLockerFactory.instances(address(locker)));
        assertTrue(clLockerFactory.instances(address(newLocker)));
        assertEq(clLockerFactory.locked(clPool), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locked(clPool, 0, 2), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locks(clPool), 2);

        _assertMappings(2, address(newLocker), address(0));

        assertEq(Ownable(address(newLocker)).owner(), users.alice);
        assertEq(address(newLocker.nfpManager()), nfpManager);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(clLockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(newLocker.pool(), clPool);
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

        assertEq(INfpm(nfpManager).ownerOf(newLocker.lp()), address(newLocker));
    }

    function test_WhenTheCallerIsThePoolLauncher_()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS_
        whenThePositionToLockExistsInTheNfpm_
    {
        // It should update locked liquidity
        // It should increment the number of locks
        // It should create the new lock
        // It shoult transfer the LP to the locker
        // It should set the instances mapping
        // It should emit a {LockerCreated} event
        uint256 liquidityBefore = clLockerFactory.locked(clPool);
        address predictedLocker = predictLockerAddress({lockerFactory: address(clLockerFactory), nonce: 2});

        vm.prank(users.alice);
        INfpm(nfpManager).safeTransferFrom({from: users.alice, to: address(clLockerFactory), tokenId: lp});

        vm.startPrank(address(clPoolLauncher));
        vm.expectCall(
            nfpManager, abi.encodeCall(INfpm.safeTransferFrom, (address(clLockerFactory), predictedLocker, lp))
        );
        vm.expectEmit(address(clLockerFactory));
        emit ILockerFactory.LockCreated({
            owner: users.alice,
            locker: predictedLocker,
            lp: lp,
            lockUntil: uint32(block.timestamp + lockDuration),
            beneficiary: users.bob,
            beneficiaryShare: 500,
            bribeableShare: 1000
        });
        ICLLocker newLocker = ICLLocker(
            clLockerFactory.lock({
                _lp: lp,
                _lockUntil: uint32(block.timestamp + lockDuration),
                _beneficiary: users.bob,
                _beneficiaryShare: 500,
                _bribeableShare: 1000,
                _owner: users.alice
            })
        );

        (,,,,,,, uint128 liquidity,,,,) = INfpm(nfpManager).positions({tokenId: lp});

        assertTrue(clLockerFactory.instances(address(locker)));
        assertTrue(clLockerFactory.instances(address(newLocker)));
        assertEq(clLockerFactory.locked(clPool), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locked(clPool, 0, 2), liquidityBefore + liquidity);
        assertEq(clLockerFactory.locks(clPool), 2);

        _assertMappings(2, address(newLocker), address(0));

        assertEq(Ownable(address(newLocker)).owner(), users.alice);
        assertEq(address(newLocker.nfpManager()), nfpManager);

        assertEq(address(newLocker.voter()), voter);
        assertEq(newLocker.factory(), address(clLockerFactory));
        assertEq(uint8(newLocker.poolType()), uint8(ILockerFactory.PoolType.CONCENTRATED));

        assertEq(newLocker.pool(), clPool);
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

        assertEq(INfpm(nfpManager).ownerOf(newLocker.lp()), address(newLocker));
    }

    function testGas_lock()
        external
        whenTheLockUntilIsGreaterThanTimestamp
        whenTheBeneficiaryIsAddressZero
        whenTheBribeableShareIsSmallerOrEqualToMAX_BPS
    {
        vm.startPrank(users.alice);
        INfpm(nfpManager).approve({to: address(clLockerFactory), tokenId: lp});
        clLockerFactory.lock({
            _lp: lp,
            _lockUntil: uint32(block.timestamp + lockDuration),
            _beneficiary: address(0),
            _beneficiaryShare: 0,
            _bribeableShare: 1000,
            _owner: users.alice
        });
        vm.snapshotGasLastCall("CLLockerFactory_lock");
    }
}
