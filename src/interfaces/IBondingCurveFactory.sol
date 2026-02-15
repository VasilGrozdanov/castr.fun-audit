// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @dev Interface for a bonding curve factory, which creates new bonding curves.
 * This interface defines the functions and events that a bonding curve factory must implement.
 */
interface IBondingCurveFactory {
    event NewBondingCurveCreated(address indexed curve);

    error BondingCurveFactory__NotActive();
    error BondingCurveFactory__NotFactoryManager();

    /**
     * @notice Creates a new bonding curve and a BurnableToken, with the specified name and symbol. The msg.sender will be set as the developer of the token.
     * @notice This function can be called directly, or will be called by the FactoryManager helper function createBondingCurve(string, string, bool) for you (see IFactoryManager). In both cases, the msg.sender will be set as the developer of the BurnableToken.
     * @notice The function is payable, allowing the user to send Ether along with the transaction, for initial funding of the bonding curve.
     * @dev it is recommended to use the FactoryManager helper function createBondingCurve(string, string, bool) instead of calling this function directly.
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param metadata The metadata of the token, which can include additional information such as description, image URL, etc. It is abi-encoded and includes (in this order): required - description, image URL; optional - Telegram, Twitter, Farcaster and Website.
     * @param isDevLocked Whether the developer's address is indefinitely locked (until the token migrates).
     * @param id A unique identifier for the creator of the bonding curve. This is used in the frontend (emitted in an event) to distinguish between different accounts with the same wallet address. The id is either the FID (Farcaster ID) or the DID (Privy's Decentralized Identifier). If you want to skip this, you can pass an empty string or '0'.
     * @return The address of the newly created bonding curve contract.
     */
    function createBondingCurve(
        string memory name,
        string memory symbol,
        bytes memory metadata,
        bool isDevLocked,
        string memory id
    ) external payable returns (address);

    /**
     * @notice Creates a new bonding curve and a BurnableToken, with the specified name and symbol. The developer's address is set to the provided address.
     * @notice The function is payable, allowing the user to send Ether along with the transaction, for initial funding of the bonding curve.
     * @dev This function is intended to be called by the FactoryManager helper function createBondingCurveFor(string, string, address, bool) for you (see IFactoryManager).
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param metadata The metadata of the token, which can include additional information such as description, image URL, etc. It is abi-encoded and includes (in this order): required - description, image URL; optional - Telegram, Twitter, Farcaster and Website.
     * @param dev The developer's address.
     * @param isDevLocked Whether the developer's address is indefinitely locked (until the token migrates).
     * @param id A unique identifier for the creator of the bonding curve. This is used in the frontend (emitted in an event) to distinguish between different accounts with the same wallet address. The id is either the FID (Farcaster ID) or the DID (Privy's Decentralized Identifier). If you want to skip this, you can pass an empty string or '0'.
     
     * @return The address of the newly created bonding curve contract.
     */
    function createBondingCurveFor(
        string memory name,
        string memory symbol,
        bytes memory metadata,
        address dev,
        bool isDevLocked,
        string memory id
    ) external payable returns (address);

    /**
     * @notice Disables the factory, preventing any further bonding curve creation.
     * @dev This function can only be called by the owner of the factory.
     */
    function disable() external;

    /**
     * @notice The BondingCurvesStorage contract is a central contract that holds all the bonding curves, as well as the FactoryManager and other related data.
     * @return The address of the bonding curves storage contract.
     */
    function bondingCurvesStorage() external view returns (address);

    /**
     * @notice Checks if the factory is active.
     * @return True if the factory is active, false otherwise.
     */
    function isActive() external view returns (bool);
}
