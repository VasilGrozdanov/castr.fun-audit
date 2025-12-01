// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILockerFactory {
    /// @notice Emitted when a new locker factory is set
    event NewLockerFactorySet(address indexed lockerFactory);
    /// @notice Emitted when a locker is migrated
    event LockerMigrated(address indexed oldLocker, address indexed newLocker, uint256 indexed lp);
    /// @notice Emitted when a locker is unlocked
    event LockerUnlocked(
        address indexed locker, address indexed underlyingPool, address indexed recipient, address refundAddress
    );
    /// @notice Emitted when a new locker is created
    event LockCreated(
        address indexed owner,
        address indexed locker,
        uint256 lp,
        uint32 lockUntil,
        address beneficiary,
        uint16 beneficiaryShare,
        uint16 bribeableShare
    );

    error NotLockerOwnerOrPoolLauncher();
    error InvalidBeneficiaryShare();
    error InsufficientUnlock0Min();
    error InsufficientUnlock1Min();
    error InvalidBribeableShare();
    error MigrationDisabled();
    error InvalidLockTime();
    error NotLockerOwner();
    error ZeroAddress();
    error ZeroAmount();
    error NotLocked();
    error NotLocker();
    error Locked();
    error Staked();

    /**
     * @notice Enum defining supported pool types
     */
    enum PoolType {
        BASIC, // 0
        CONCENTRATED // 1

    }

    /**
     * @notice Unlocks an LP from the given locker and transfers it to the recipient
     * @param _locker The address of the locker to unlock
     * @param _recipient The recipient to receive the LP
     */
    function unlock(address _locker, address _recipient) external;

    /**
     * @notice Migrates an existing locker into a new locker factory deployment
     * @dev Only callable if `newLockerFactory` is set
     * @param _locker The address of the locker to migrate
     * @param _unlock0Min Minimum amount of token0 to unlock from the old LP
     * @param _unlock1Min Minimum amount of token1 to unlock from the old LP
     * @param _amount0Min Minimum amount of token0 to migrate to the new locker
     * @param _amount1Min Minimum amount of token1 to migrate to the new locker
     * @return The amount of token0 unlocked
     * @return The amount of token1 unlocked
     * @return The address of the new locker instance, or zero if the migration is done by the pool launcher
     * @dev If called by the pool launcher, it should unlock to be used in the new pool launcher.
     *         If the pool already exists in the new pool launcher, the function will revert at the pool launcher level.
     * @dev If called by the user, the funds will be migrated to the new locker factory.
     *            The new pool should exist in the pool factory. Otherwise, it will revert.
     */
    function migrate(
        address _locker,
        uint256 _unlock0Min,
        uint256 _unlock1Min,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external returns (uint256, uint256, address);

    /**
     * @notice Sets a new locker factory address
     * @param _lockerFactory The address of the new locker factory
     * @dev This function can only be called by the owner of the contract
     */
    function setNewLockerFactory(address _lockerFactory) external;

    /**
     * @notice Called by locker._transferOwnership to update locker mappings
     * @param _owner The current owner of the locker
     * @param _newOwner The new owner of the locker
     * @param _pool The pool associated with the locker
     * @dev Only callable by the locker
     */
    function transferLockerOwnership(address _owner, address _newOwner, address _pool) external;

    /**
     * @notice Denominator for the calculation of shares (as basis points)
     * @return The denominator for the calculation of shares
     */
    function MAX_BPS() external view returns (uint256);

    /**
     * @notice The address of the voter contract
     * @return Address of the voter
     */
    function voter() external view returns (address);

    /**
     * @notice The address of the pool launcher contract, used to launch pools
     * @return Address of the pool launcher
     */
    function poolLauncher() external view returns (address);

    /**
     * @notice The address of the locker implementation, used to deploy new lockers
     * @return Address of the locker implementation
     */
    function lockerImplementation() external view returns (address);

    /**
     * @notice The pool type supported by the locker factory
     * @return Type of pools supported by the locker factory
     */
    function poolType() external view returns (PoolType);

    /**
     * @notice The address of the newly deployed locker factory, used to migrate existing locker positions
     * @dev If set to the zero address, migrations are disabled
     * @return Address of the new locker factory
     */
    function newLockerFactory() external view returns (address);

    /**
     * @notice Get the number of active locks for a specific pool
     * @param _pool The pool to get the locks for
     * @return The amount of total active locks
     */
    function locks(address _pool) external view returns (uint256);

    /**
     * @notice Get the total locked liquidity for a specific pool
     * @param _pool The pool to get the locked liquidity for
     * @return The amount of total locked liquidity
     */
    function locked(address _pool) external view returns (uint256);

    /**
     * @notice Get the total locked liquidity for a specific pool in a given range (segment of the lockers)
     * @param _pool The pool to get the locked liquidity for
     * @param _start The start of the range (inclusive)
     * @param _end The end of the range (exclusive)
     * @return The amount of locked liquidity
     */
    function locked(address _pool, uint256 _start, uint256 _end) external view returns (uint256);

    /**
     * @notice Check if an address is a locker instance
     * @param _locker The address to check
     * @return True if the address is a locker instance, false otherwise
     */
    function instances(address _locker) external view returns (bool);

    /**
     * @notice Get the list of lockers for a specific pool
     * @param _pool The pool to get the lockers for
     * @return An array of locker addresses
     */
    function lockers(address _pool) external view returns (address[] memory);

    /**
     * @notice Get a paginated list of lockers for a specific pool
     * @param _pool The pool to get the lockers for
     * @param _start The starting index (inclusive)
     * @param _end The ending index (exclusive)
     * @return An array of locker addresses in the specified range
     */
    function lockers(address _pool, uint256 _start, uint256 _end) external view returns (address[] memory);

    /**
     * @notice Get the count of lockers for a specific pool
     * @param _pool The pool to get the locker count for
     * @return The number of lockers associated with the pool
     */
    function lockersCount(address _pool) external view returns (uint256);

    /**
     * @notice Get the list of lockers owned by a specific user
     * @param _user The user to get the lockers for
     * @return An array of locker addresses owned by the user
     */
    function lockersPerUser(address _user) external view returns (address[] memory);

    /**
     * @notice Get a paginated list of lockers owned by a specific user
     * @param _user The user to get the lockers for
     * @param _start The starting index (inclusive)
     * @param _end The ending index (exclusive)
     * @return An array of locker addresses owned by the user in the specified range
     */
    function lockersPerUser(address _user, uint256 _start, uint256 _end) external view returns (address[] memory);

    /**
     * @notice Get the count of lockers owned by a specific user
     * @param _user The user to get the locker count for
     * @return The number of lockers owned by the user
     */
    function lockersPerUserCount(address _user) external view returns (uint256);

    /**
     * @notice Get the list of lockers for a specific pool owned by a specific user
     * @param _pool The pool to get the lockers for
     * @param _user The user to get the lockers for
     * @return An array of locker addresses associated with the pool and owned by the user
     */
    function lockersPerPoolPerUser(address _pool, address _user) external view returns (address[] memory);

    /**
     * @notice Get a paginated list of lockers for a specific pool owned by a specific user
     * @param _pool The pool to get the lockers for
     * @param _user The user to get the lockers for
     * @param _start The starting index (inclusive)
     * @param _end The ending index (exclusive)
     * @return An array of locker addresses associated with the pool and owned by the user in the specified range
     */
    function lockersPerPoolPerUser(address _pool, address _user, uint256 _start, uint256 _end)
        external
        view
        returns (address[] memory);

    /**
     * @notice Get the count of lockers for a specific pool owned by a specific user
     * @param _pool The pool to get the locker count for
     * @param _user The user to get the locker count for
     * @return The number of lockers associated with the pool and owned by the user
     */
    function lockersPerPoolPerUserCount(address _pool, address _user) external view returns (uint256);
}
