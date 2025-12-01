// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGauge {
    event ClaimRewards(address indexed from, uint256 amount);
    event Deposit(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake);
    event Withdraw(address indexed user, uint256 indexed tokenId, uint128 indexed liquidityToStake);

    function rewardToken() external view returns (address);

    function earned(address account, uint256 tokenId) external view returns (uint256);
    function earned(address _account) external view returns (uint256 _earned);

    function getReward(address account) external;
    function getReward(uint256 tokenId) external;

    function deposit(uint256 lp) external;
    function withdraw(uint256 lp) external;

    function notifyRewardWithoutClaim(uint256 amount) external;

    function gaugeFactory() external view returns (address);
    function balanceOf(address account) external view returns (uint256);

    function periodFinish() external view returns (uint256);
}
