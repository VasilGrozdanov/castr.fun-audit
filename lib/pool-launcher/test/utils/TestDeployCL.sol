// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {DeployCLFixture} from "script/DeployCLFixture.s.sol";

contract TestDeployCL is DeployCLFixture {
    constructor(DeployCLFixture.DeploymentParameters memory _params_) {
        _params = _params_;
        isTest = true;
    }

    function setUp() public override {}
}
