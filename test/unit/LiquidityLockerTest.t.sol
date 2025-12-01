// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {LiquidityMigrator} from "src/LiquidityMigrator.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {LiquidityLocker, ILiquidityLocker} from "src/LiquidityLocker.sol";

contract LockManagerTest is Test {
    address liquidityMigrator = makeAddr("liquidityMigrator");
    address feeAccount = makeAddr("feeAccount");
    address USER = makeAddr("user");
    LiquidityLocker liquidityLocker;

    function setUp() external {
        liquidityLocker = new LiquidityLocker(liquidityMigrator);
    }

    function testSetLiquidityMigratorOk() external {
        address newLiquidityMigrator = makeAddr("newLiquidityMigrator");
        address owner = liquidityLocker.owner();

        vm.prank(owner);
        liquidityLocker.setLiquidityMigrator(newLiquidityMigrator);
        assertEq(
            address(liquidityLocker.liquidityMigrator()),
            newLiquidityMigrator
        );
    }

    function testSetLiquidityMigratorReverts() external {
        address newLiquidityMigrator = makeAddr("newLiquidityMigrator");
        vm.prank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                USER
            )
        );
        liquidityLocker.setLiquidityMigrator(newLiquidityMigrator);
    }

    function testLockReverts() external {
        vm.expectRevert(
            ILiquidityLocker.LiquidityLocker__NotLiquidityMigrator.selector
        );
        liquidityLocker.lock(0, address(0));
    }
}
