// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPoolLauncher {
    /// @notice Emitted when a new pool launcher pool is launched
    event Launch(
        address indexed poolLauncherToken,
        address indexed pool,
        address indexed sender,
        PoolLauncherPool poolLauncherPool
    );
    /// @notice Emitted when an underlying pool and locker are migrated to a new pool launcher
    event Migrate(
        address indexed underlyingPool, address indexed locker, PoolLauncherPool newPoolLauncherPool, address newLocker
    );
    /// @notice Emitted when a pool is flagged as emerging
    event EmergingFlagged(address indexed pool, uint256 indexed timestamp);
    /// @notice Emitted when a pool is unflagged as emerging
    event EmergingUnflagged(address indexed pool);
    /// @notice Emitted when a pairable token is added
    event PairableTokenAdded(address indexed token);
    /// @notice Emitted when a pairable token is removed
    event PairableTokenRemoved(address indexed token);
    /// @notice Emitted when a new pool launcher is set
    event NewPoolLauncherSet(address indexed newPoolLauncher);
    /// @notice Emitted when a new creation timestamp is set for a pool
    event CreationTimestampSet(address indexed pool, uint256 createdAt);

    error InsufficientTokenToPairUnlockMin();
    error InsufficientPoolLauncherUnlockMin();
    error InvalidPoolLauncherToken();
    error TokenAlreadyRegistered();
    error InvalidNewPoolLauncher();
    error InvalidLockerForPool();
    error InvalidRefundAddress();
    error PoolNotInPoolLauncher();
    error NewPoolLauncherNotSet();
    error TokenNotRegistered();
    error PoolAlreadyExists();
    error InvalidTimestamp();
    error NotLockerOwner();
    error InvalidLocker();
    error ZeroTimestamp();
    error InvalidToken();
    error ZeroAddress();
    error NotLocked();

    /// @notice Pool launcher pool
    struct PoolLauncherPool {
        /// @notice timestamp of the pool creation
        uint32 createdAt;
        /// @notice address of the underlying pool
        address pool;
        /// @notice address of the pool launcher token
        address poolLauncherToken;
        /// @notice address of the token to pair
        address tokenToPair;
    }

    /**
     * @notice Migrates the pool launcher pool to the new pool launcher contract
     * @param _locker The address of the locker to migrate, used to provide liquidity
     * @param _poolLauncherUnlockMin Minimum amount of pool launcher token to unlock from the old Locker
     * @param _tokenToPairUnlockMin Minimum amount of token to pair to unlock from the old Locker
     * @param _poolLauncherAmountMin Minimum amount of pool launcher token to migrate
     * @param _tokenToPairAmountMin Minimum amount of token to pair to migrate
     * @return The migrated pool launcher pool
     * @return The address of the new locker used to provide liquidity
     */
    function migrate(
        address _locker,
        uint256 _poolLauncherUnlockMin,
        uint256 _tokenToPairUnlockMin,
        uint256 _poolLauncherAmountMin,
        uint256 _tokenToPairAmountMin
    ) external returns (PoolLauncherPool memory, address);

    /**
     * @notice Sets the address for the new pool launcher
     * @param _newPoolLauncher The address of the new pool launcher contract
     */
    function setNewPoolLauncher(address _newPoolLauncher) external;

    /**
     * @notice Flag a pool as emerging
     * @param _pool The address of the pool to flag
     * @param _timestamp The timestamp when the pool was flagged as emerging
     */
    function flagEmerging(address _pool, uint256 _timestamp) external;

    /**
     * @notice Unflag a pool as emerging
     * @param _pool The address of the pool to unflag
     */
    function unflagEmerging(address _pool) external;

    /**
     * @notice Updates the creation timestamp for an existing pool
     * @param _pool The address of the pool
     * @param _createdAt The new creation timestamp for the pool
     */
    function setCreationTimestamp(address _pool, uint32 _createdAt) external;

    /**
     * @notice Add a token to the list of pairable tokens
     * @param _token The address of the token to add
     */
    function addPairableToken(address _token) external;

    /**
     * @notice Remove a token from the list of pairable tokens
     * @param _token The address of the token to remove
     */
    function removePairableToken(address _token) external;

    /**
     * @notice The address of the locker factory, used to create lockers for seed liquidity
     * @return Address of the locker factory
     */
    function lockerFactory() external view returns (address);

    /*
      * @notice The address of the new pool launcher to migrate positions to
      * @return Address of the new pool launcher 
      */
    function newPoolLauncher() external view returns (address);

    /**
     * @notice Returns the PoolLauncherPool information for the given pool
     * @param _underlyingPool The address of the pool to query
     * @return The PoolLauncherPool details for the underlying pool
     */
    function pools(address _underlyingPool) external view returns (PoolLauncherPool memory);

    /**
     * @notice Returns when a pool was flagged as emerging
     * @param _pool The address of the pool to get the timestamp for
     * @return _timestamp The time at which the pool was flagged as emerging
     */
    function emerging(address _pool) external view returns (uint256 _timestamp);

    /**
     * @notice Get the total number of pairable tokens
     * @return The number of pairable tokens
     */
    function getPairableTokensCount() external view returns (uint256);

    /**
     * @notice Get the token at the specified index from all pairable tokens
     * @param _index The index of the token to retrieve
     * @return The address of the token
     */
    function getPairableTokenAt(uint256 _index) external view returns (address);

    /**
     * @notice Check if an token can be paired against
     * @param _token The address to check
     * @return True if the address is a relay, false otherwise
     */
    function isPairableToken(address _token) external view returns (bool);

    /**
     * @notice Get all pairable tokens
     * @return An array of all token addresses
     */
    function getAllPairableTokens() external view returns (address[] memory);
}
