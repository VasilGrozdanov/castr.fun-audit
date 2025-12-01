//SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @dev Interface for a LockPositionsNFT contract that represents locked positions.
 * @notice Each token represents a lock position with details such as amount, lock shares, unlock time, locked at time, and more. It is used by the lock manager contract to mint and manage locked positions. See ILockManager for more details.
 */
interface ILockPositionsNFT is IERC721 {
    struct Position {
        uint256 amount;
        uint256 lockShares;
        uint256 unlockTime;
        uint256 lockedAtTime;
    }
    struct SvgParams {
        Position position;
        uint256 tokenId;
        address lockedToken;
        address minter;
        address lockManager;
        uint256 blockTimestamp;
        uint256 lockBoost;
    }
    struct IdsOwned {
        mapping(uint256 tokenId => uint256 index) indexes;
        uint256[] ids;
    }

    event MetadataUpdate(uint256 _tokenId);

    error LockPositionsNFT__NotOwnerOf(uint256 tokenId);

    /**
     * @dev Function to burn a token, only callable by the owner.
     * @param tokenId The ID of the token to burn.
     */
    function burn(uint256 tokenId) external;

    /**
     * @dev Function to safely transfer a token to another address, only callable by the owner of the token.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     */
    function safeTransfer(address to, uint256 tokenId) external;

    /**
     * @dev Function to transfer a token from one address to another, emitting a MetadataUpdate event (for the NFT marketplaces). Caller must be pre-approved.
     * @param from The address to transfer the token from.
     * @param to The address to transfer the token to.
     * @param tokenId The ID of the token to transfer.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Function to mint a new token with a position, only callable by the owner.
     * @param to The address to mint the token to.
     * @param position The position details to associate with the token.
     * @return tokenId The ID of the newly minted token.
     */
    function mint(
        address to,
        Position memory position
    ) external returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @notice Initializes the LockPositionsNFT contract with the given parameters.
     * @dev This function is called during the deployment of the contract to set up initial values.
     *
     * @param _name The name of the NFT collection.
     * @param _symbol The symbol of the NFT collection.
     * @param _lockedToken The address of the token that is being locked in the positions.
     */
    function initialize(
        string memory _name,
        string memory _symbol,
        address _lockedToken
    ) external;

    /**
     * @notice Retrieves the position details for a given token ID.
     *
     * @param tokenId The ID of the token to retrieve the position for.
     * @return amount The amount of tokens locked in the position.
     * @return lockShares The number of shares associated with the locked position.
     * @return unlockTime The unlock time of the position.
     * @return lockedAtTime The time the position was locked.
     */
    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint256 amount,
            uint256 lockShares,
            uint256 unlockTime,
            uint256 lockedAtTime
        );

    /**
     * @notice Getter for the next token ID to be minted.
     * @dev One-based index, so the first token ID will be 1.
     *
     * @return The next token ID.
     */
    function nextTokenId() external view returns (uint256);

    /**
     * @notice Getter for the token, that is being locked.
     * @dev This is the token that is being locked in the positions.
     *
     * @return The address of the locked token contract.
     */
    function lockedToken() external view returns (address);

    /**
     * @notice Returns the token IDs owned by a specific address.
     *
     * @param owner The address of the owner to get the token IDs for.
     * @param skip The number of token IDs to skip (for pagination).
     * @param limit The maximum number of token IDs to return.
     */
    function getOwnedTokenIds(
        address owner,
        uint256 skip,
        uint256 limit
    ) external view returns (uint256[] memory);

    /**
     * @notice Generates the SVG representation of a token's position.
     * @param tokenId The ID of the token to generate the SVG for.
     * @return The SVG string representing the token's position.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
