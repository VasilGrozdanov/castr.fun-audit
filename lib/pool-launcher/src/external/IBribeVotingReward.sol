// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBribeVotingReward {
    function notifyRewardAmount(address token, uint256 amount) external;
}
