// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {DeployV2Fixture} from "../../DeployV2Fixture.s.sol";

contract DeployPoolLauncher is DeployV2Fixture {
    function setUp() public override {
        _params = DeployV2Fixture.DeploymentParameters({
            v2Factory: 0xF1046053aa5682b4F9a81b5481394DA16BE5FF5a,
            v2Router: 0xa062aE8A9c5e11aaA026fc2670B0D65cCc8B2858,
            voter: 0x41C914ee0c7E1A5edCD0295623e6dC557B5aBf3C,
            owner: address(0), //placeholder
            outputFilename: "optimism.json"
        });
    }
}
