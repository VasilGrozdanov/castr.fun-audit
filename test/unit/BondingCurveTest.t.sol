// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BondingCurve, IBondingCurve} from "src/BondingCurve.sol";
import {Test} from "forge-std/Test.sol";
import {LiquidityMigratorMock} from "test/mocks/LiquidityMigratorMock.t.sol";
import {AddressChecker} from "src/AddressChecker.sol";
import {BondingCurveFactory} from "src/BondingCurveFactory.sol";
import {BondingCurvesStorage} from "src/BondingCurvesStorage.sol";
import {FactoryManager} from "src/FactoryManager.sol";
import {BurnableToken, IBurnableTokenActions, IBurnableTokenContext} from "src/BurnableToken.sol";
import {LockPositionsNFT} from "src/LockPositionsNFT.sol";
import {LockManager} from "src/LockManager.sol";

contract BondingCurveTest is Test {
    uint256 constant START_AMOUNT = 0.0529411764705882 ether;
    uint256 constant MINIMAL_AMOUNT = 0.001 ether;
    uint256 constant GOAL_AMOUNT = 4.5 ether;
    IBurnableTokenActions burnableToken;
    BondingCurve bondingCurve;
    LiquidityMigratorMock liquidityMigrator;
    address USER = makeAddr("castr_test_user_unique");
    address FEE_ACCOUNT = makeAddr("feeAccount");
    uint256 maxLockDuration;
    BondingCurveFactory bondingCurveFactory;
    BondingCurvesStorage bondingCurvesStorage;
    FactoryManager factoryManager;
    address[] dexes;
    string constant ID = "1";

    function setUp() public {
        liquidityMigrator = new LiquidityMigratorMock(FEE_ACCOUNT);

        dexes.push(address(0));
        AddressChecker addressChecker = new AddressChecker(dexes);
        BondingCurvesStorage bondingCurvesStorageImpl = new BondingCurvesStorage();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(bondingCurvesStorageImpl),
            ""
        );
        bondingCurvesStorage = BondingCurvesStorage(address(proxy));
        BondingCurve bondingCurveImpl = new BondingCurve();
        BurnableToken burnableTokenImpl = new BurnableToken();
        LockManager lockManagerImpl = new LockManager();
        LockPositionsNFT lockPositionsNFTImpl = new LockPositionsNFT();
        bondingCurvesStorage.initialize(
            address(liquidityMigrator),
            address(addressChecker),
            address(bondingCurveImpl),
            address(burnableTokenImpl),
            address(lockManagerImpl),
            address(lockPositionsNFTImpl)
        );
        FactoryManager factoryManagerImpl = new FactoryManager();
        proxy = new ERC1967Proxy(address(factoryManagerImpl), "");
        factoryManager = FactoryManager(address(proxy));
        bondingCurveFactory = new BondingCurveFactory(
            address(bondingCurvesStorage)
        );
        factoryManager.initialize(address(bondingCurveFactory));
        bondingCurvesStorage.setFactoryManager(address(factoryManager));
        bondingCurve = BondingCurve(
            payable(
                factoryManager.createBondingCurve("Test", "TEST", "", false, ID)
            )
        );
        burnableToken = bondingCurve.token();
        vm.deal(USER, 4.5529411764705882 ether);
        vm.warp(block.timestamp + 6 seconds);
        vm.roll(block.number + 3);
        maxLockDuration = bondingCurve.MAX_LOCK_DURATION();
    }

    function testSniperProtected() external {
        bondingCurve = BondingCurve(
            payable(
                factoryManager.createBondingCurve("Test", "TEST", "", false, ID)
            )
        );

        vm.expectRevert(IBondingCurve.BondingCurve__Protected.selector);
        _sendEtherToCurve(START_AMOUNT);
    }

    function testBuyOk() public {
        uint256 startingBalanceBondingCurve = address(bondingCurve).balance;
        uint256 startingTokenBalanceBondingCurve = burnableToken.balanceOf(
            address(bondingCurve)
        );
        uint256 startingBalanceUser = address(USER).balance;

        vm.prank(USER);
        (bool success, ) = _sendEtherToCurve(START_AMOUNT);

        assertTrue(success);
        assertGt(burnableToken.balanceOf(USER), 0);
        assertEq(
            burnableToken.balanceOf(address(bondingCurve)),
            startingTokenBalanceBondingCurve - burnableToken.balanceOf(USER)
        );
        assertGt(address(bondingCurve).balance, startingBalanceBondingCurve);
        assertLt(address(USER).balance, startingBalanceUser);
        assertGt(FEE_ACCOUNT.balance, 0);
    }

    function testBuyForDevOk() public {
        uint256 startingBalanceBondingCurve = address(bondingCurve).balance;
        uint256 startingTokenBalanceBondingCurve = burnableToken.balanceOf(
            address(bondingCurve)
        );
        uint256 startingBalance = address(this).balance;
        address factory = factoryManager.getBondingCurveFactory();
        address dev = makeAddr("dev");

        vm.deal(factory, START_AMOUNT);
        vm.prank(factory);
        bondingCurve.buyTokenForDev{value: START_AMOUNT}(dev, 0, ID);

        assertGt(burnableToken.balanceOf(dev), 0);
        assertEq(
            burnableToken.balanceOf(address(bondingCurve)),
            startingTokenBalanceBondingCurve - burnableToken.balanceOf(dev)
        );
        assertGt(address(bondingCurve).balance, startingBalanceBondingCurve);
        assertLt(dev.balance, startingBalance);
        assertGt(FEE_ACCOUNT.balance, 0);
    }

    function testSellOk() public {
        testBuyOk();
        uint256 startingFeeAccountBalance = FEE_ACCOUNT.balance;
        uint256 startingBalanceBondingCurve = address(bondingCurve).balance;
        uint256 startingTokenBalanceBondingCurve = burnableToken.balanceOf(
            address(bondingCurve)
        );
        uint256 startingTokenBalanceUser = burnableToken.balanceOf(USER);
        uint256 startingBalanceUser = address(USER).balance;
        vm.warp(block.timestamp + 24 hours);
        vm.roll(block.number + 1);

        vm.startPrank(USER);
        burnableToken.approve(address(bondingCurve), startingTokenBalanceUser);
        bondingCurve.sellToken(startingTokenBalanceUser, 0, ID);
        vm.stopPrank();

        assertEq(burnableToken.balanceOf(USER), 0);
        assertEq(
            burnableToken.balanceOf(address(bondingCurve)),
            startingTokenBalanceBondingCurve + startingTokenBalanceUser
        );
        assertLt(address(bondingCurve).balance, startingBalanceBondingCurve);
        assertGt(address(USER).balance, startingBalanceUser);
        assertGt(FEE_ACCOUNT.balance, startingFeeAccountBalance);
    }

    function testSellRevertsIfStillLocked() public {
        testBuyOk();
        uint256 startingTokenBalanceUser = burnableToken.balanceOf(USER);

        vm.startPrank(USER);
        burnableToken.approve(address(bondingCurve), startingTokenBalanceUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnableTokenContext.BurnableToken__TransfersLocked.selector,
                block.timestamp + 24 hours
            )
        );
        bondingCurve.sellToken(startingTokenBalanceUser, 0, ID);
        vm.stopPrank();
    }

    function testSellRevertsIfMinAmountNotMet() public {
        testBuyOk();
        uint256 startingTokenBalanceUser = burnableToken.balanceOf(USER);

        vm.warp(block.timestamp + 24 hours);
        vm.roll(block.number + 1);
        vm.startPrank(USER);
        burnableToken.approve(address(bondingCurve), startingTokenBalanceUser);
        vm.expectRevert(
            IBondingCurve.BondingCurve__MinimumAmountNotMet.selector
        );
        bondingCurve.sellToken(startingTokenBalanceUser, type(uint256).max, ID);
        vm.stopPrank();
    }

    function testBuyRevertsIfMinAmountNotMet() public {
        uint256 startingBalanceUser = address(USER).balance;

        vm.prank(USER);
        vm.expectRevert(
            IBondingCurve.BondingCurve__MinimumAmountNotMet.selector
        );
        bondingCurve.buyToken{value: START_AMOUNT}(type(uint256).max, ID);
    }

    function testBuyForDevRevertsIfNotFactory() public {
        uint256 startingBalanceUser = address(USER).balance;

        vm.expectRevert(
            IBondingCurve.BondingCurve__NotBondingCurveFactory.selector
        );
        bondingCurve.buyTokenForDev{value: START_AMOUNT}(address(this), 0, ID);
    }

    function testCantSellWhenNotOnCurve() public {
        vm.startPrank(USER);
        _sendEtherToCurve(GOAL_AMOUNT + START_AMOUNT);
        burnableToken.approve(address(bondingCurve), USER.balance);
        uint256 userTokenBalance = burnableToken.balanceOf(USER);

        vm.expectRevert(
            IBondingCurve.BondingCurve__TokenAlreadyBonded.selector
        );
        bondingCurve.sellToken(userTokenBalance, 0, ID);
        vm.stopPrank();
    }

    function testCantBuyWhenNotOnCurve() public {
        vm.startPrank(USER);
        _sendEtherToCurve(GOAL_AMOUNT + START_AMOUNT);
        burnableToken.approve(address(bondingCurve), USER.balance);

        vm.expectRevert(
            IBondingCurve.BondingCurve__TokenAlreadyBonded.selector
        );
        address(bondingCurve).call{value: 1}("");
        vm.stopPrank();
    }

    function testSetsLaunchedWhenNotOnCurve() public {
        vm.startPrank(USER);
        _sendEtherToCurve(GOAL_AMOUNT + START_AMOUNT);
        vm.stopPrank();
        assertTrue(burnableToken.isLaunched());
        assertEq(
            BurnableToken(payable(address(burnableToken))).owner(),
            address(0)
        );
        assertEq(bondingCurvesStorage.currentKingOfTheCasts(), address(0));
    }

    function testVestingPreMigrationExtendedTime() external {
        uint256 additionalTime = 982 seconds; // this is calcualted dynamically, change if the second buy amount changes
        uint256 expectedTime = block.timestamp +
            maxLockDuration +
            additionalTime;
        vm.prank(USER);
        (bool success, ) = _sendEtherToCurve(GOAL_AMOUNT);
        vm.warp(block.timestamp + maxLockDuration);
        vm.prank(USER);
        _sendEtherToCurve(MINIMAL_AMOUNT);
        (uint256 duration, , , ) = burnableToken.holdersVesting(USER);

        assertEq(duration, expectedTime);
    }

    function testVestingPreMigrationSameTime() external {
        uint256 expectedTime = block.timestamp + maxLockDuration;

        vm.prank(USER);
        (bool success, ) = _sendEtherToCurve(GOAL_AMOUNT);
        vm.warp(block.timestamp + maxLockDuration / 2);
        vm.prank(USER);
        _sendEtherToCurve(MINIMAL_AMOUNT);
        (uint256 duration, , , ) = burnableToken.holdersVesting(USER);

        assertEq(duration, expectedTime);
    }

    function _sendEtherToCurve(
        uint256 amount
    ) public returns (bool, bytes memory) {
        return address(bondingCurve).call{value: amount}("");
    }
}
