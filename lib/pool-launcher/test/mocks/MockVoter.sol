// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IVoter} from "src/external/IVoter.sol";

contract MockVoter is IVoter {
    function ve() external view returns (address) {}
    function gauges(address pool) external view returns (address) {}
    function gaugeToBribe(address gauge) external view returns (address) {}
    function gaugeToIncentive(address gauge) external view returns (address) {}

    function claimRewards(address[] calldata _gauges) external {}

    function createGauge(address, address) external returns (address) {}
    function governor() external view returns (address) {}
}
