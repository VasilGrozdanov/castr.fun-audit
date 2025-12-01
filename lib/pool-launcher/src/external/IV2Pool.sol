// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IV2Pool {
    event Claim(address indexed sender, address indexed recipient, uint256 amount0, uint256 amount1);

    function poolFees() external view returns (address);
    function tokens() external returns (address, address);
    function balanceOf(address account) external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function stable() external view returns (bool);

    function claimFees() external returns (uint256 claimed0, uint256 claimed1);

    function skim(address to) external;

    function token0() external view returns (address);

    function token1() external view returns (address);
}
