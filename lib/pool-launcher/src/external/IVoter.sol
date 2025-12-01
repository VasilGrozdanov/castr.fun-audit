// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVoter {
    function ve() external view returns (address);
    function governor() external view returns (address);
    function gauges(address pool) external view returns (address);
    function gaugeToBribe(address gauge) external view returns (address);
    function gaugeToIncentive(address gauge) external view returns (address);
    function createGauge(address poolFactory, address pool) external returns (address);
}
