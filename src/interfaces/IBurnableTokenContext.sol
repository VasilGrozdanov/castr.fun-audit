//SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @dev Interface for a burnable token context.
 * This interface defines the errors and events related to burnable tokens, including dividend distribution and transfer locking.
 */
interface IBurnableTokenContext {
    error BurnableToken__NotOwnerOrLaunched(address sender);
    error BurnableToken__NotLaunched();
    error BurnableToken__TransfersLocked(uint256 unlockTime);
    error BurnableToken__UnvestedAmount(uint256 unlockTime, uint256 amount);
    error BurnableToken__DevIsLocked();
    error BurnableToken__MustBeMoreThanZero();
    error BurnableToken__NotEnoughBalance(uint256 amount, uint256 balance);
    error BurnableToken__BurnAmountExceedsBalance();
    error BurnableToken__ZeroAddressChecker();
    error BurnableToken__NotFeeAccount();
    error BurnableToken__NotDev();
    error BurnableToken__NotLockManager();

    event DividendsDistributed(address indexed sender, uint256 amount);
    event DividendWithdrawn(address indexed receiver, uint256 amount);
    event TransfersLockExtended(address indexed holder, uint256 newUnlockTime);
}
