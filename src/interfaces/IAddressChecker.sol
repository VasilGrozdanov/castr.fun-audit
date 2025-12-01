//SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @dev Interface for checking if an address is a registered DEX.
 * This interface allows for the management of DEX addresses, including adding and removing them.
 */
interface IAddressChecker {
    /**
     * @param dex The address to check.
     * @return True if the address is a registered DEX, false otherwise.
     */
    function isDex(address dex) external returns (bool);

    /**
     * @notice Adds a new DEX address to the list of registered DEXs.
     * @param dex The address of the DEX to add. Only callable by the owner.
     */
    function addDex(address dex) external;

    /**
     * @notice Removes a DEX address from the list of registered DEXs.
     * @param dex The address of the DEX to remove. Only callable by the owner.
     */
    function removeDex(address dex) external;
}
