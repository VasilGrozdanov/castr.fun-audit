// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IGauge} from "../external/IGauge.sol";
import {IVoter} from "../external/IVoter.sol";
import {ILockerFactory} from "../interfaces/ILockerFactory.sol";

interface ILocker {
    event FeesClaimed(address indexed recipient, uint256 claimed0, uint256 claimed1);
    event RewardsClaimed(address indexed recipient, uint256 claimed);
    event Staked();
    event Unstaked();
    event Unlocked(address indexed recipient, address indexed refundAddress);
    event Bribed(address indexed pool, address indexed token, uint256 amount);
    event BribeableShareSet(uint16 indexed newBribeableShare);
    event UnlockTimestampIncreased(uint256 newUnlockTimestamp);
    event LiquidityIncreased(uint256 indexed amount0, uint256 indexed amount1, uint256 indexed liquidity);
    event Swept(address indexed token, address indexed recipient, uint256 indexed amount);

    error NotFactory();
    error InvalidBribeableShare();
    error InvalidPercentage();
    error AlreadyStaked();
    error PermanentLock();
    error InvalidToken();
    error ZeroDuration();
    error ZeroAddress();
    error ZeroAmount();
    error NotStaked();
    error NotLocked();
    error NoGauge();
    error LockerStaked();

    /**
     * @notice Initializes the state of the Locker contract
     * @param _owner The owner of the locker
     * @param _pool The underlying pool for the locked LP
     * @param _lp The amount of LP tokens or the token ID to be locked.
     * @param _lockedUntil The timestamp until which the position will be locked
     * @param _beneficiary Optional address that will receive `_bribeableShare` of claimed fees/rewards
     * @param _beneficiaryShare The percentage of claimed fees/rewards that will be sent to the beneficiary (0-10000)
     * @param _bribeableShare The percentage of claimed fees/rewards that will be bribeable by external parties (0-10000)
     */
    function initialize(
        address _owner,
        address _pool,
        uint256 _lp,
        uint32 _lockedUntil,
        address _beneficiary,
        uint16 _beneficiaryShare,
        uint16 _bribeableShare
    ) external;

    /**
     * @notice Unlocks the locked position and transfers the position to the recipient
     * @dev Assumes the unlock timestamp has passed
     * @param _recipient The address to receive the unlocked position
     * @param _refundAddress The address to receive any leftover tokens from the locker
     * @return The amount of LP tokens or the token ID transferred to the recipient
     */
    function unlock(address _recipient, address _refundAddress) external returns (uint256);

    /**
     * @notice Stakes the locked position in the gauge
     */
    function stake() external;

    /**
     * @notice Unstakes the locked position from the gauge
     */
    function unstake() external;

    /**
     * @notice Claims fees from the locked position and transfers them to the recipient
     * @param _recipient The address to receive the claimed fees
     * @return claimed0 The amount of token0 claimed
     * @return claimed1 The amount of token1 claimed
     */
    function claimFees(address _recipient) external returns (uint256 claimed0, uint256 claimed1);

    /**
     * @notice Claims rewards from the gauge and transfers them to the recipient
     * @param _recipient The address to receive the claimed rewards
     * @return claimed The amount of rewards claimed
     */
    function claimRewards(address _recipient) external returns (uint256 claimed);

    /**
     * @notice Bribes the pool for which the liquidity is locked with the percentage of clamimed fees/rewards
     * @dev anyone can call this function, but only the owner can use percentage higher greater than bribeableShare
     * @param _percentage the percentage of fees/rewards to bribe (0-10000)
     */
    function bribe(uint16 _percentage) external;

    /**
     * @notice Increases the liquidity of the locked position by adding more of token0 and token1
     * @param _amount0 The amount of token0 to add
     * @param _amount1 The amount of token1 to add
     * @param _amount0Min The minimum amount of token0 to deposit
     * @param _amount1Min The minimum amount of token1 to deposit
     * @return The amount of liquidity tokens minted to the locker
     */
    function increaseLiquidity(uint256 _amount0, uint256 _amount1, uint256 _amount0Min, uint256 _amount1Min)
        external
        returns (uint256);

    /**
     * @notice Extends the lock duration of the locker
     * @dev If `_duration` is set to `type(uint32).max`, the locker will be permanently locked
     *      Overflow is possible if the new unlock timestamp to be set exceeds `type(uint32).max`
     * @param _duration The number of seconds to increase the lock duration by
     */
    function increaseDuration(uint32 _duration) external;

    /**
     * @notice Sets the maximum percentage of rewards that can be deposited into the underlying pool as incentives
     * @param _bribeableShare The maximum share of rewards that can be deposited into the underlying pool
     */
    function setBribeableShare(uint16 _bribeableShare) external;

    /**
     * @notice Denominator for the calculation of shares (as basis points)
     * @return The denominator for the calculation of shares
     */
    function MAX_BPS() external view returns (uint256);

    /**
     * @notice Chain ID of the base chain (8453)
     * @return The chain ID
     */
    function BASE_CHAIN_ID() external view returns (uint256);

    /**
     * @notice The address of the voter contract
     * @return Address of the voter
     */
    function voter() external view returns (IVoter);

    /**
     * @notice The address of the factory that created this locker
     * @return Address of the locker factory
     */
    function factory() external view returns (address);

    /**
     * @notice The address of the reward token used in gauges
     * @return Address of the reward token
     */
    function rewardToken() external view returns (address);

    /**
     * @notice The type of the Locker's underlying pool
     * @return Type of the underlying pool
     */
    function poolType() external view returns (ILockerFactory.PoolType);

    /**
     * @notice Check whether the locker is on the root chain
     * @return True if the locker is on the root chain, false otherwise
     * @dev Root chain is OP Mainnet (block.chainid=10)
     */
    function root() external view returns (bool);

    /**
     * @notice The address of the pool for which the liquidity is locked
     * @return Address of the underlying pool
     */
    function pool() external view returns (address);

    /**
     * @notice The first of the two tokens of the underlying pool, sorted by address
     * @return The token contract address
     */
    function token0() external view returns (address);

    /**
     * @notice The second of the two tokens of the underlying pool, sorted by address
     * @return The token contract address
     */
    function token1() external view returns (address);

    /**
     * @notice The liquidity position locked in the locker
     * @dev Returns the amount of LP tokens for V2 positions, or the LP token ID for CL positions
     * @return The underlying liquidity position
     */
    function lp() external view returns (uint256);

    /**
     * @notice The address of the gauge for the locker's underlying pool
     * @return Address of the gauge for the underlying pool
     */
    function gauge() external view returns (IGauge);

    /**
     * @notice The address eligible for a share of rewards accrued by the liquidity position
     * @return Recipient of the share of rewards
     */
    function beneficiary() external view returns (address);

    /**
     * @notice The percentage of rewards that the beneficiary is eligible for, in basis points
     * @return Share of rewards for the beneficiary
     */
    function beneficiaryShare() external view returns (uint16);

    /**
     * @notice The maximum share of rewards that can be deposited as incentives
     * @return Share of rewards that can be used as incentives
     */
    function bribeableShare() external view returns (uint16);

    /**
     * @notice The timestamp until which the liquidity position is locked
     * @return Unlock timestamp
     */
    function lockedUntil() external view returns (uint32);

    /**
     * @notice Check whether the liquidity position is staked in a gauge
     * @return True if the liquidity position is staked, false otherwise
     */
    function staked() external view returns (bool);
}
