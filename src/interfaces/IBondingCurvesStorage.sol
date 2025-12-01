// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {FactoryManager} from "src/FactoryManager.sol";

interface IBondingCurvesStorage {
    event NewBondingCurveCreated(
        address indexed curve,
        address indexed token,
        address indexed creator,
        string name,
        string symbol,
        bool isDevLocked,
        string id,
        bytes metadata
    );
    event FeePercentUpdated(uint16 indexed newFeePercent);
    event DevRewardsWithdrawn(address indexed dev, uint256 indexed amount);
    event NewKingOfTheCasts(address indexed curve);
    event Buy(
        address indexed token,
        address indexed sender,
        uint256 indexed amount,
        uint256 deposit,
        string id,
        uint256 unlockTime
    );
    event Sell(
        address indexed token,
        address indexed sender,
        uint256 indexed amount,
        uint256 reimbursement,
        string id
    );

    error BondingCurvesStorage__InvalidFeePercent();
    error BondingCurvesStorage__NotBondingCurve();
    error BondingCurvesStorage__NotBondingCurveFactory();
    error BondingCurvesStorage__ZeroAddress();
    error BondingCurvesStorage__WithdrawalFailed();

    /**
     * @notice Distributes the creator's rewards.
     *
     * @param dev The address of the creator to receive rewards.
     */
    function receiveDevReward(address dev) external payable;

    /**
     * @notice Withdraws the creator's rewards.
     * @dev Creator rewards are accumulated and can be withdrawn any time.
     */
    function withdrawDevRewards() external;

    /**
     * @dev This function emits an event when a token is bought on the bonding curve.
     * Can only be called by the BondingCurve contract.
     *
     * @param token The address of the token being bought.
     * @param sender The address of the sender who bought the token.
     * @param amount The amount of tokens bought.
     * @param deposit The amount of ETH deposited for the purchase.
     * @param id The unique identifier for the frontend (either Farcaster FID or Privy's DID).
     * @param unlockTime The unlock time for the total bought tokens. This includes previous purchases, meaniong the time is additive. The locking blocks both token transfers and calling the sell function. It doesn't affect the buy function.
     */
    function emitBuy(
        address token,
        address sender,
        uint256 amount,
        uint256 deposit,
        string memory id,
        uint256 unlockTime
    ) external;

    /**
     * @dev This function emits an event when a token is sold on the bonding curve.
     * Can only be called by the BondingCurve contract.
     *
     * @param token The address of the token being sold.
     * @param sender The address of the sender who sold the token.
     * @param amount The amount of tokens sold.
     * @param reimbursement The amount of ETH reimbursed to the sender.
     * @param id The unique identifier for the frontend (either Farcaster FID or Privy's DID).
     */
    function emitSell(
        address token,
        address sender,
        uint256 amount,
        uint256 reimbursement,
        string memory id
    ) external;

    /**
     * @dev This function emits an event when a new bonding curve is created. Can only be called by the FactoryManager.
     *
     * @param curve The address of the bonding curve to emit the event for.
     * @param token The address of the token associated with the bonding curve.
     * @param creator The address of the creator of the token.
     * @param name The name of the bonding curve token.
     * @param symbol The symbol of the bonding curve token.
     * @param isDevLocked Whether the developer's tokens are locked.
     * @param id The unique identifier for the frontend (either Farcaster FID or Privy's DID).
     * @param metadata Additional metadata asociated with the token.
     */
    function emitNewBondingCurveCreated(
        address curve,
        address token,
        address creator,
        string memory name,
        string memory symbol,
        bool isDevLocked,
        string memory id,
        bytes memory metadata
    ) external;

    /**
     * @dev This function can only be called by the FactoryManager.
     * @param bondingCurve The address of the bonding curve to add.
     */
    function addBondingCurve(address bondingCurve) external;

    /**
     * @notice Checks if the given address is a registered bonding curve.
     * @param curve The address of the bonding curve to check.
     * @return True if the address is a registered bonding curve, false otherwise.
     */
    function bondingCurves(address curve) external view returns (bool);

    /**
     * @return The second to last king of the casts, meaning the second to last token that reached half of the funding goal.
     */
    function lastKingOfTheCasts() external view returns (address);

    /**
     * @return The current king of the casts, meaning the last token that reached half of the funding goal.
     */
    function currentKingOfTheCasts() external view returns (address);

    /**
     * @notice Updates the current king of the casts.
     * @dev This function can only be called by the tracked BondingCurve contracts.
     * @param newKingOfTheCasts The address of the new king of the casts.
     * @param isCrowned Whether the new king of the casts is crowned already or not.
     */
    function updateKingOfTheCasts(
        address newKingOfTheCasts,
        bool isCrowned
    ) external;

    /**
     * @notice Removes the last king of the casts.
     * @dev This function can only be called by the tracked BondingCurve contracts.
     */
    function removeLastKingOfTheCasts() external;

    /**
     * @notice Adds a new NFT to the list of based NFTs.
     * @dev This function can only be called by the owner.
     * @param nft The address of the NFT contract to add.
     */
    function addBasedNFT(address nft) external;

    /**
     * @notice Gets the address of a based NFT by its index.
     *
     * @param index The index of the based NFT to retrieve.
     * @return nft The address of the based NFT at the specified index.
     */
    function basedNFTs(uint256 index) external view returns (address nft);

    /**
     * @return The address of the AddressChecker contract.
     */
    function getAddressChecker() external view returns (address);

    /**
     * @dev The FactoryManager contract is responsible for managing the creation of bonding curves, from a single point.
     * @return The address of the FactoryManager contract.
     */
    function factoryManager() external view returns (FactoryManager);

    /**
     * @notice Returns the fee percentage for the bonding curves.
     * @return The fee percentage as a uint16, scaled by 1000 (e.g., 10 represents 1%).
     */
    function feePercent() external view returns (uint16);

    /**
     * @notice The bonding curve is holding the token. King of the casts requires the funding goal to be half-reached.
     * @param curve The address of the bonding curve to check.
     * @return timestamp The timestamp when the token in the bonding curve was crowned king of the casts or 0 if not crowned yet.
     */
    function crownedCasts(
        address curve
    ) external view returns (uint256 timestamp);

    /**
     * @dev The LiquidityMigrator contract is responsible for migrating liquidity from the bonding curves to Aerodrome Concentrated Liquidity, when the funding goal is reached.
     * @return The address of the LiquidityMigrator contract.
     */
    function liquidityMigrator() external view returns (address);

    /**
     * @dev The BondingCurve implementation contract is used to create new BondingCurves.
     * @return The address of the BondingCurve implementation contract.
     */
    function bondingCurveImplementation() external view returns (address);

    /**
     * @dev The BurnableToken implementation contract is used to create new BurnableTokens for the bonding curves.
     * @return The address of the BurnableToken implementation contract.
     */
    function burnableTokenImplementation() external view returns (address);

    /**
     * @dev The LockManager implementation contract is used to create new LockManagers for the bonding curves.
     * @return The address of the LockManager implementation contract.
     */
    function lockManagerImplementation() external view returns (address);

    /**
     * @dev The LockPositionsNFT implementation contract is used to create new LockPositionsNFTs for the bonding curves.
     * @return The address of the LockPositionsNFT implementation contract.
     */
    function lockPositionsNFTImplementation() external view returns (address);
}
