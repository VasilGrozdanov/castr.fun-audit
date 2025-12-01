// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import "../../../BaseForkFixture.sol";

abstract contract CLPoolLauncherTest is BaseForkFixture {
    function test_InitialState() public view {
        assertEq(address(clPoolLauncher.nfpManager()), nfpManager);
        assertEq(address(clPoolLauncher.clFactory()), clFactory);
        assertEq(address(clPoolLauncher.lockerFactory()), address(clLockerFactory));

        assertEq(clPoolLauncher.getPairableTokensCount(), 1);
        assertEq(clPoolLauncher.getPairableTokenAt({_index: 0}), address(usdc));
        assertTrue(clPoolLauncher.isPairableToken({_token: address(usdc)}));
        address[] memory pairableTokens = clPoolLauncher.getAllPairableTokens();
        assertEq(pairableTokens.length, 1);
        assertEq(pairableTokens[0], address(usdc));
    }
}
