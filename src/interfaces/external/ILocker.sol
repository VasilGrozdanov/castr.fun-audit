// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// @dev Interface for Aerodrome's Locker contract.
interface ILocker {
    /**
     * @notice Claims fees from the locked position and transfers them to the recipient
     * @param _recipient The address to receive the claimed fees
     * @return claimed0 The amount of token0 claimed
     * @return claimed1 The amount of token1 claimed
     */
    function claimFees(
        address _recipient
    ) external returns (uint256 claimed0, uint256 claimed1);
}
