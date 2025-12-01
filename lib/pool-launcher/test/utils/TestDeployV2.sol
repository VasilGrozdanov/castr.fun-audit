// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {DeployV2Fixture} from "script/DeployV2Fixture.s.sol";

contract TestDeployV2 is DeployV2Fixture {
    constructor(DeployV2Fixture.DeploymentParameters memory _params_) {
        _params = _params_;
        isTest = true;
    }

    function setUp() public override {}
}
