// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

// import {ILockPositionsNFT} from "src/interfaces/ILockPositionsNFT.sol";
import {ILockPositionsNFT} from "src/interfaces/ILockPositionsNFT.sol";
import {IDividendToken} from "src/interfaces/IDividendToken.sol";

/**
 * @dev Interface for a lock manager that handles locking positions, distributing rewards, and managing dividends.
 * This interface defines the functions and events that a lock manager must implement.
 */
interface ILockManager {
    error LockManager__MustBeMoreThanZero();
    error LockManager__NotFeeAccountOrToken();
    error LockManager__PoisitionNotUnlocked();
    error LockManager__NotAuthorized();
    error LockManager__NotOwner(uint256 tokenId);
    error LockManager__LockDurationUnderMinForUnvestedAmount(
        uint256 unvestedAmount,
        uint256 duration
    );

    event PositionLocked(
        address indexed sender,
        uint256 indexed amount,
        uint256 indexed duration
    );
    event RewardsDistributed(uint256 amount);
    event LockClaimed(address indexed receiver, uint256 amount);
    event DividendWithdrawn(address indexed receiver, uint256 amount);
    event DividendsDistributed(address indexed sender, uint256 amount);

    /**
     * @notice Initializes the lock manager with the given parameters.
     * @dev This function is called during the deployment of the contract to set up initial values.
     *
     * @param dividendToken The address of the dividend token that will be locked.
     * @param feeAccount The address of the fee account that will receive fees.
     * @param lockPositionsNFTImpl The address of the implementation of the LockPositionsNFT contract.
     */
    function initialize(
        address dividendToken,
        address feeAccount,
        address lockPositionsNFTImpl
    ) external;

    /**
     * @notice Locks the selected position and mints a LockPositionsNFT representing the lock, to the caller (msg.sender).
     * @param amount Amount of tokens to lock. Must be greater than 0 and pre-approved to transfer.
     * @param durationInDays Duration of the lock in days. Caps at 365 days. Must be greater than 0.
     * @return tokenId - The tokenId of the minted position NFT.
     */
    function lock(
        uint256 amount,
        uint256 durationInDays
    ) external returns (uint256 tokenId);

    /**
     * @notice Locks the selected position and mints a LockPositionsNFT representing the lock, to the specified lockOwner.
     * @dev This function can be called only by the locked token contract.
     *
     * @param lockOwner The address that will own the locked position.
     * @param amount Amount of tokens to lock. Must be greater than 0 and pre-approved to transfer.
     * @param durationInDays Duration of the lock in days. Caps at 365 days. Must be greater than 0.
     * @param isBoosted Whether the lock is boosted with an initial boost.
     * @return tokenId - The tokenId of the minted position NFT.
     */
    function lockFor(
        address lockOwner,
        uint256 amount,
        uint256 durationInDays,
        bool isBoosted
    ) external returns (uint256 tokenId);

    /**
     * @notice Distributes dividends to the position NFT holders.
     * @dev Callable by anyone, but only if the msg.value is greater than 0.
     */
    function distributeDividends() external payable;

    /**
     * @notice distributes rewards to the position NFT holders.
     * @dev Callable only by the fee account or the token contract.
     *
     * @param amount The amount of rewards to distribute in wei.
     */
    function distributeRewards(uint256 amount) external;

    /**
     * @notice Claims the rewards distributed to the position NFT + the initial locked amount, and burns the NFT.
     * @param tokenId The tokenId of the position NFT.
     */
    function claimRewards(uint256 tokenId) external;

    /**
     * @param tokenId The tokenId of the position NFT.
     * @notice Collects the rewards distributed to the position NFT.
     */
    function collectRewards(uint256 tokenId) external;

    /**
     * @param tokenId The tokenId of the position NFT.
     * @notice Collects the dividends (ETH) from the locked tokens, of the position NFT to its owner.
     */
    function collectDividends(uint256 tokenId) external;

    /**
     * @param tokenId The tokenId of the position NFT.
     * @notice utillity function for collection both the rewards distributed to the position NFT and the dividends (ETH) from the locked tokens, of the position NFT to its owner.
     * @dev packs collectRewards and collectDividends in a single call.
     */
    function collectRewardsAndDividends(uint256 tokenId) external;

    /**
     * @notice Returns the address of the LockPositionsNFT contract that manages the locked positions.
     * @return The address of the LockPositionsNFT contract.
     */
    function positionsNFT() external view returns (ILockPositionsNFT);

    /**
     * @notice View the amount of reward in wei that a NFT position has collected.
     * @param tokenId The tokenId of the position NFT.
     * @return The amount of reward in wei, that a NFT position can be collect (locked until the position expires and the NFT gets burned).
     */
    function collectableRewardOf(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice View the amount of reward in wei, that a NFT position has collected.
     * @param tokenId The tokenId of the position NFT.
     * @return The amount of reward in wei that a NFT position has collected.
     */
    function collectedRewardOf(uint256 tokenId) external view returns (uint256);

    /**
     * @notice View the amount of reward in wei that a NFT position has collected in total.
     * @dev accumulativeDividendOf(tokenId) = collectableDividendOf(tokenId) + collectedDividendOf(tokenId)
     * = ((totalDividends / totalLockShares) * lockedTokensNFT.positions(tokenId).lockShares / magnitude
     * @param tokenId The tokenId of the position NFT.
     * @return The amount of reward in wei that the NFT position with tokenId has earned in total.
     */
    function accumulativeRewardOf(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice View the amount of reward in wei that a NFT position has collected.
     * @param tokenId The tokenId of the position NFT.
     * @return The amount of dividends (ETH) in wei, from the locked tokens, that a NFT position can collect.
     */
    function collectableDividendOf(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice View the amount dividends (ETH) in wei, from the locked tokens, that a NFT position has collected.
     * @param tokenId The tokenId of the position NFT.
     * @return The amount of dividends (ETH) in wei, from the locked tokens, that a NFT position has collected.
     */
    function collectedDividendOf(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice View the amount of dividends (ETH) in wei, from the locked tokens, that a NFT position has collected in total.
     * @dev accumulativeDividendOf(tokenId) = collectableDividendOf(tokenId) + collectedDividendOf(tokenId)
     * = ((totalDividends / totalLockShares) * lockedTokensNFT.positions(tokenId).lockShares / magnitude
     * @param tokenId The tokenId of the position NFT.
     * @return The amount of dividends (ETH) in wei, from the locked tokens, that a NFT position has earned in total.
     */
    function accumulativeDividendOf(
        uint256 tokenId
    ) external view returns (uint256);

    /**
     * @notice Returns the instance of the locked dividend token contract.
     * @return The instance of the locked dividend token contract.
     */
    function dividendToken() external view returns (IDividendToken);
}
