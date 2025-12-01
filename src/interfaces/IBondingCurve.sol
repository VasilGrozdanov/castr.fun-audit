// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IBurnableTokenActions} from "src/interfaces/IBurnableTokenActions.sol";

/**
 * @dev Interface for a bonding curve contract.
 * This interface defines the functions and events that a bonding curve must implement.
 */
interface IBondingCurve {
    event Buy(
        address indexed sender,
        uint256 amount,
        uint256 deposit,
        string id,
        uint256 unlockTime
    );
    event Sell(
        address indexed sender,
        uint256 amount,
        uint256 reimbursement,
        string id
    );

    error BondingCurve__AmountMustBePositive();
    error BondingCurve__AmountMustBeMoreThanMin();
    error BondingCurve__MinimumAmountNotMet();
    error BondingCurve__AmountMoreThanBalance();
    error BondingCurve__TokenNotBonded();
    error BondingCurve__TokenAlreadyBonded();
    error BondingCurve__TransferFailed();
    error BondingCurve__Protected();
    error BondingCurve__Locked(uint256 unlockTime);

    /**
     * @dev Initializes the bonding curve contract with the necessary parameters.
     * @dev This contract is intended to be created by a bonding curve factory, or by the factory manager (see IBondingCurveFactory and IFactoryManager).
     *
     * @param name The name of the token.
     * @param symbol The symbol of the token.
     * @param _metadata The metadata of the token, which can include additional information such as description, image URL, etc.
     * @param feePercent The fee percentage for transactions.
     * @param liquidityMigrator The address of the liquidity migrator contract.
     * @param _feeAccount The address that will receive fees.
     * @param _isDevLocked Whether the developer's tokens are locked.
     * @param _dev The address of the developer.
     */
    function initialize(
        string memory name,
        string memory symbol,
        bytes memory _metadata,
        uint16 feePercent,
        address liquidityMigrator,
        address _feeAccount,
        bool _isDevLocked,
        address _dev
    ) external;

    /**
     * @notice This function allows users to sell tokens they hold on the bonding curve for ETH.
     * @notice The function uses tx.origin as a sender and reciever, which is the original caller of the transaction.
     * @notice The function is blocked from being called if the tx.origin is locked from transfering (see extendLockDuration(address,uint256) in IBurnableTokenActions).
     * @dev It transfers the specified amount of tokens from the caller to the contract and then calculates the reimbursement amount based on the bonding curve's sell logic.
     * It ensures that the amount to be sold is positive and that the minimum amount to be received is met.
     * It also checks that the caller has enough tokens to sell and that the bonding curve is not locked (until the token migrates).
     * Emits a Sell event upon successful completion.
     *
     * @param amount The amount of tokens to sell.
     * @param minAmount The minimum amount of tokens to receive in return.
     * @param id A unique identifier for the creator of the bonding curve. This is used in the frontend (emitted in an event) to distinguish between different accounts with the same wallet address. The id is either the FID (Farcaster ID) or the DID (Privy's Decentralized Identifier). If you want to skip this, you can pass an empty string or '0'.
     */
    function sellToken(
        uint256 amount,
        uint256 minAmount,
        string memory id
    ) external;

    /**
     * @notice This function allows users to buy tokens from the bonding curve using ETH.
     * @notice The function uses tx.origin as a sender and reciever, which is the original caller of the transaction.
     * @notice The function is NOT blocked from being called if the tx.origin is locked from transfering (see extendLockDuration(address,uint256) in IBurnableTokenActions).
     * @dev It calculates the amount of tokens to be bought based on the bonding curve's buy logic and ensures that the minimum amount of tokens to be received is met.
     * It also checks that the bonding curve is not locked (until the token migrates).
     * Emits a Buy event upon successful completion.
     *
     * @param minAmount The minimum amount of tokens to receive in return for the ETH sent.
     * @param id A unique identifier for the creator of the bonding curve. This is used in the frontend (emitted in an event) to distinguish between different accounts with the same wallet address. The id is either the FID (Farcaster ID) or the DID (Privy's Decentralized Identifier). If you want to skip this, you can pass an empty string or '0'.
     */
    function buyToken(uint256 minAmount, string memory id) external payable;

    /**
     * @notice This function calculates how much tokens can be bought for a specified amount of ETH on the bonding curve. This does not include the fee.
     *
     * @param _amount The amount of tokens to buy.
     * @return The amount of ETH to be sent in order to buy the specified amount of tokens.
     */
    function calculateContinuousBuyReturn(
        uint256 _amount
    ) external view returns (uint256);

    /**
     * @notice This function calculates how much ETH can be received for a specified amount of tokens on the bonding curve. This does not include the fee.
     *
     * @param _amount The amount of tokens to sell.
     * @return The amount of ETH to be received in return for the specified amount of tokens.
     */
    function calculateContinuousSellReturn(
        uint256 _amount
    ) external view returns (uint256);

    /**
     * @notice This function calculates the fee amount to be charged by the protocol for a given amount of tokens being bought or sold.
     *
     * @param amount The amount of tokens to buy or sell.
     * @return The fee amount to be charged by the protocol.
     */
    function calculateFee(uint256 amount) external view returns (uint256);

    /**
     * @dev Once the bonding curve is created, it is operational and once the token migrates it is deactivated. Buy and sell operations will revert if the bonding curve is not operational. It cannot be reactivated.
     * @return Whether the bonding curve is currently active and operational.
     */
    function isOnCurve() external view returns (bool);

    /**
     * @notice This function returns the instance of the BurnableToken associated with this bonding curve.
     * @return The instance of the BurnableToken contract.
     */
    function token() external view returns (IBurnableTokenActions);

    /**
     * @return The raised amount of ETH in the bonding curve.
     */
    function getReserveBalance() external view returns (uint256);

    /**
     * @notice The FeeAccount contract manages the collected fees.
     * @return The address of the FeeAccount contract.
     */
    function feeAccount() external view returns (address);

    /**
     * @notice The ILiquidityMigrator contract manages the migration of tokens and creaing liquidity pools.
     * @return The address of the ILiquidityMigrator contract.
     */
    function migrator() external view returns (address);

    /**
     * @dev The bonding curve factories can change. Use IFactoryManager to get the current active factory and for centralized creation of bonding curves.
     * @return The address of the bonding curve factory that created this bonding curve.
     */
    function factory() external view returns (address);

    /**
     * @dev For more information on the token locking pre-migration see IBurnableTokenActions.
     *
     * @return The minimum locking duration in seconds for the bought tokens.
     */
    function MIN_LOCK_DURATION() external view returns (uint256);

    /**
     * @dev For more information on the token locking pre-migration see IBurnableTokenActions.
     *
     * @return The maximum locking duration in seconds for the bought tokens.
     */
    function MAX_LOCK_DURATION() external view returns (uint256);
}
