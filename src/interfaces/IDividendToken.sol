//SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev Interface for a dividend token.
 * This interface defines the functions and events that a token with dividends must implement.
 */
interface IDividendToken is IERC20Metadata {
    function distributeDividends() external payable;

    /**
     * @notice Withdraws the ether distributed to the sender.
     */
    function withdrawDividend() external;

    /**
     * @notice View the amount of dividend in wei that an address can withdraw.
     * @param _owner The address of a token holder.
     * @return The amount of dividend in wei that `_owner` can withdraw.
     */
    function withdrawableDividendOf(
        address _owner
    ) external view returns (uint256);

    /**
     * @notice View the amount of dividend in wei that an address has withdrawn.
     * @param _owner The address of a token holder.
     * @return The amount of dividend in wei that `_owner` has withdrawn.
     */
    function withdrawnDividendOf(
        address _owner
    ) external view returns (uint256);

    /**
     * @notice View the amount of dividend in wei that an address has earned in total.
     * @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
     * = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
     * @param _owner The address of a token holder.
     * @return The amount of dividend in wei that `_owner` has earned in total.
     */
    function accumulativeDividendOf(
        address _owner
    ) external view returns (uint256);
}
