//SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {ICLPool} from "@velodrome-finance/slipstream/core/interfaces/ICLPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IBurnableTokenActions} from "src/interfaces/IBurnableTokenActions.sol";
import {RewardResolver} from "src/RewardResolver.sol";

/**
 * @dev Interface for interacting with the fee account contract.
 */
interface IFeeAccount {
    enum State {
        OPEN,
        CALCULATING
    }

    struct TokenRefferences {
        ICLPool pool;
        IBurnableTokenActions instance;
        IERC20 otherToken;
        address locker;
    }

    // Custom error type
    error FeeAccount__NotLiquidityMigratorOrLocker();
    error FeeAccount__NotGraduatedToken();
    error FeeAccount__ZeroAddress();
    error FeeAccount__LockerInitialized();
    error FeeAccount__TransferFailed();
    error FeeAccount__UpkeepNotNeeded(RewardResolver.State rewardResolverState);

    // Event to log responses
    event Rewarded(
        address indexed pool,
        address indexed token,
        uint256 amount,
        uint256 timestamp
    );
    event MigratorUpdated(address indexed newMigrator);
    event NewLockManagerAndNFT(
        address indexed lockManager,
        address indexed lockNFT,
        address indexed token
    );

    /**
     * @notice Emits a NewLockManagerAndNFT event.
     * @dev This function can only be called by a burnable token, that has migrated and is part of the competing tokens.
     *
     * @param lockNFT The address of the lock NFT contract.
     */
    function emitNewLockManagerAndNFT(
        address lockManager,
        address lockNFT
    ) external;

    /**
     * @notice Collects fees generated in the token's pool, distributes them among holders and dev, and rewards the caller. The reward in WETH is calculated as collectedWethAmount * collectRewardPercent / FEE_SCALE (scale of thousand).
     * @notice dev reward is not immediately transferred, but locked for a period of time (devRewardsCliff) in a lock position NFT. The lock NFT is transferred to the dev, so they can unclock the reward, once the lock expires. If the dev address is a contract, it must implement the IERC721Receiver interface to receive the lock NFT. Otherwise the reward will be distributed to the lock position NFT holders.
     *
     * @param token The address of the token to collect fees from its Aerodrome Concentrated Liquidity pool and burn
     */
    function collectFeesAndDistribute(address payable token) external;

    /**
     * @notice Adds a competing token to the FeeAccount contract.
     * @dev This function can only be called by the ILiquidityMigrator.
     *
     * @param token The address of the token to add (must be a non-zero address).
     * @param otherToken The address of the other token in the Aerodrome Concentrated Liquidity pool for the token.
     * @param pool The address of the Aerodrome Concentrated Liquidity pool for the token.
     * @param locker The locker created for the liquidity position.
     */
    function addCompetingToken(
        address payable token,
        address otherToken,
        address pool,
        address locker
    ) external;

    /**
     * @param token The isntance of the token address.
     */
    function getCompetingTokenRefferences(
        address token
    ) external view returns (TokenRefferences memory);
}
