// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "test/BaseForkFixture.sol";

contract V2PoolLauncherTest is BaseForkFixture {
    function test_InitialState() public view {
        assertEq(address(v2PoolLauncher.v2Factory()), v2Factory);
        assertEq(address(v2PoolLauncher.lockerFactory()), address(v2LockerFactory));
        assertEq(v2PoolLauncher.getPairableTokensCount(), 1);
        assertEq(v2PoolLauncher.getPairableTokenAt(0), address(usdc));
        assertTrue(v2PoolLauncher.isPairableToken(address(usdc)));

        address[] memory pairableTokens = v2PoolLauncher.getAllPairableTokens();
        assertEq(pairableTokens.length, 1);
        assertEq(pairableTokens[0], address(usdc));
    }
}
