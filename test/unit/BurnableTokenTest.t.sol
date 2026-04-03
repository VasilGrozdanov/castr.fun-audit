// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Power} from "src/Power.sol";
import {BurnableToken} from "src/BurnableToken.sol";
import {Test} from "forge-std/Test.sol";
import {AddressChecker} from "src/AddressChecker.sol";
import {IBurnableTokenContext} from "src/interfaces/IBurnableTokenContext.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract BurnableTokenTest is Test {
    BurnableToken burnableToken;
    BurnableToken devLockedBurnableToken;
    address USER = makeAddr("castr_test_user_unique");
    address OWNER = makeAddr("castr_test_owner_unique");
    address DEX = makeAddr("castr_test_dex_unique");
    uint256 GOAL_AMOUNT = 4.5 ether;
    address[] dexes;

    function setUp() public {
        dexes.push(DEX);
        AddressChecker addressChecker = new AddressChecker(dexes);
        BurnableToken burnableTokenImpl = new BurnableToken();
        address clone = Clones.clone(address(burnableTokenImpl));
        burnableToken = BurnableToken(payable(clone));
        vm.prank(OWNER);
        burnableToken.initialize(
            "Test",
            "TEST",
            "",
            address(addressChecker),
            false,
            OWNER,
            address(0),
            address(0),
            address(0)
        );
        clone = Clones.clone(address(burnableTokenImpl));
        devLockedBurnableToken = BurnableToken(payable(clone));
        vm.prank(OWNER);
        devLockedBurnableToken.initialize(
            "Test",
            "TEST",
            "",
            address(addressChecker),
            true,
            OWNER,
            address(0),
            address(0),
            address(0)
        );
    }

    function testCreateRevertsInvalidNameCharacters() external {
        (
            AddressChecker addressChecker,
            BurnableToken _burnableToken
        ) = _setUpToken();
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__InvalidName.selector
        );
        _burnableToken.initialize(
            "Test!",
            "TEST",
            "",
            address(addressChecker),
            false,
            OWNER,
            address(0),
            address(0),
            address(0)
        );
    }

    function testCreateRevertsInvalidNameLength() external {
        (
            AddressChecker addressChecker,
            BurnableToken _burnableToken
        ) = _setUpToken();
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__InvalidName.selector
        );
        _burnableToken.initialize(
            "Test          Too          Long!",
            "TEST",
            "",
            address(addressChecker),
            false,
            OWNER,
            address(0),
            address(0),
            address(0)
        );
    }

    function testCreateRevertsInvalidSymbolCharacters() external {
        (
            AddressChecker addressChecker,
            BurnableToken _burnableToken
        ) = _setUpToken();
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__InvalidSymbol.selector
        );
        _burnableToken.initialize(
            "Test",
            "TEST!",
            "",
            address(addressChecker),
            false,
            OWNER,
            address(0),
            address(0),
            address(0)
        );
    }

    function testCreateRevertsInvalidSymbolLength() external {
        (
            AddressChecker addressChecker,
            BurnableToken _burnableToken
        ) = _setUpToken();
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__InvalidSymbol.selector
        );
        _burnableToken.initialize(
            "Test",
            "TESTTOOLOONG",
            "",
            address(addressChecker),
            false,
            OWNER,
            address(0),
            address(0),
            address(0)
        );
    }

    function testTransferToEaoOk() external {
        vm.prank(OWNER);
        burnableToken.transfer(USER, GOAL_AMOUNT);
        assertEq(GOAL_AMOUNT, burnableToken.balanceOf(USER));
    }

    function testTransferToDexReverts() external {
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IBurnableTokenContext
                    .BurnableToken__NotOwnerOrLaunched
                    .selector,
                USER
            )
        );
        burnableToken.transfer(DEX, GOAL_AMOUNT);
    }

    function testLockPriorToMigrationReverts() external {
        uint256 amount = burnableToken.balanceOf(OWNER);
        uint256 duration = 1;
        vm.prank(OWNER);
        burnableToken.approve(address(burnableToken), amount);

        vm.prank(OWNER);
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__NotLaunched.selector
        );
        burnableToken.lock(amount, duration);
    }

    function testTransferFromLockedDevReverts() external {
        vm.prank(OWNER);
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__DevIsLocked.selector
        );
        devLockedBurnableToken.transfer(USER, GOAL_AMOUNT);
    }

    function testChangeDevRevertsWhenNotLaunched() external {
        vm.prank(OWNER);
        vm.expectRevert(
            IBurnableTokenContext.BurnableToken__NotLaunched.selector
        );
        devLockedBurnableToken.setDev(USER);
    }

    function testChangeDevRevertsWhenNotDev() external {
        vm.expectRevert(IBurnableTokenContext.BurnableToken__NotDev.selector);
        devLockedBurnableToken.setDev(USER);
    }

    function _setUpToken() private returns (AddressChecker, BurnableToken) {
        AddressChecker addressChecker = new AddressChecker(dexes);
        BurnableToken burnableTokenImpl = new BurnableToken();
        address clone = Clones.clone(address(burnableTokenImpl));
        BurnableToken token = BurnableToken(payable(clone));
        return (addressChecker, token);
    }
}
