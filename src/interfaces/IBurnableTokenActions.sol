//SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev Interface for a burnable token actions.
 * This interface defines the functions that a token within a bonding curve must implement.
 */
interface IBurnableTokenActions is IERC20Metadata {
    /**
     * @notice Burns a specified amount of tokens from the caller's balance.
     * @notice Prior to the burn, the accumulated dividends are distributed to the caller.
     * @dev This function overrides the burn function of the ERC20 standard.
     * It includes checks for vesting, launch status, and developer lock.
     * @param amount The amount of tokens to burn.
     */
    function burn(uint256 amount) external;

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() external;

    /**
     * @notice Sets the migration timestamp.
     * @dev This function can only be called by the owner.
     * @param liquidityAmount The amount of tokens, that were used for liquidity on migration.
     */
    function setMigrated(uint256 liquidityAmount) external;

    /**
     * @notice Sets the token as launched.
     * @dev This function can only be called by the owner.
     */
    function setLaunched() external;

    /**
     * @notice Extends the lock duration of a holder. This blocks the holder from all tranfers for a specified amount of time, except for transfers made to the LockManager (if the token has migrated).
     * @dev This function can only be called by the owner.
     *
     * @param _holder The holder whose lock duration is to be extended.
     * @param _newUnlockTime The new unlock time to be set, if it is greater than the current unlock time.
     */
    function extendLockDuration(
        address _holder,
        uint256 _newUnlockTime
    ) external;

    /**
     * @notice Adds locked vesting amount for a holder.
     * @dev This function can only be called by the LockManager.
     *
     * @param holder The address of the holder to add locked amount to.
     * @param amount The amount of locked amount to be added.
     */
    function addLockedAmount(address holder, uint256 amount) external;

    /**
     * @notice Locks the selected position and mints a LockPositionsNFT representing the lock, to the caller (msg.sender).
     * @notice Uses LockManager. For the other functions, see the ILockManager interface.
     * @param amount Amount of tokens to lock. Must be greater than 0 and pre-approved to transfer.
     * @param durationInDays Duration of the lock in days. Caps at 365 days. Must be greater than 0.
     * @return tokenId - The tokenId of the minted position NFT.
     */
    function lock(
        uint256 amount,
        uint256 durationInDays
    ) external returns (uint256 tokenId);

    /**
     * @dev Initializes the BurnableToken contract. This function can be called only by the owner of the contract.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _metadata The metadata of the token, which can include additional information such as description, image URL, etc.
     * @param addressChecker The address of the IAddressChecker contract.
     * @param _isDevLocked Boolean indicating if the developer's address is locked.
     * @param _dev The address of the developer (creator) of the token.
     * @param _feeAccount The address that receives fees.
     * @param _lockManagerImpl The address of the lock manager implementation contract.
     * @param _lockPositionsNFTImpl The address of the lock positions NFT implementation contract.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        bytes memory _metadata,
        address addressChecker,
        bool _isDevLocked,
        address _dev,
        address _feeAccount,
        address _lockManagerImpl,
        address _lockPositionsNFTImpl
    ) external;

    /**
     * @notice Checks if the token is launched.
     * @return True if the token is launched, false otherwise.
     */
    function isLaunched() external view returns (bool);

    /**
     * @dev Returns the address of the creator of this token.
     *
     * @return The address of the creator.
     */
    function dev() external view returns (address);

    /**
     * @notice Returns the total amount of tokens locked for the holder, until vested, the unlock time (pre and post migration) and the amount of tokens locked post-migration in the LockPositionsNFT(of the total amount of tokens locked for vesting).
     *
     * @param holder The address of the holder to check.
     * @return unlockTimePreMigration The unlock time before migration to Aerodrome Concentrated Liquidity pool.
     * @return unlockTimePostMigration The unlock time after migration to Aerodrome Concentrated Liquidity pool.
     * @return amount The total amount of tokens locked for the holder.
     * @return lockedAmount The amount of tokens that the holder locked post-migration in the LockPositionsNFT to earn rewards.
     */
    function holdersVesting(
        address holder
    )
        external
        view
        returns (
            uint256 unlockTimePreMigration,
            uint256 unlockTimePostMigration,
            uint256 amount,
            uint256 lockedAmount
        );

    /**
     * @notice Calculates the unlock time and the amount of tokens vested post-migration for the holder. Transfers to the LockManager (for locking) are exempt from this.
     * @dev This is utility function, for getting the unlock time and amount before it's available via holdersVesting(address).
     *
     * @param holder The address of the holder to check.
     * @return unlockTime The unlock time after migration to Aerodrome Concentrated Liquidity pool.
     * @return amount The amount of tokens that the holder has vested post-migration.
     */
    function calculateHolderVestingPostMigration(
        address holder
    ) external view returns (uint256 unlockTime, uint256 amount);
}
