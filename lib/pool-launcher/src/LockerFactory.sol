// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {ILockerFactory} from "./interfaces/ILockerFactory.sol";
import {ILocker} from "./interfaces/ILocker.sol";

/// @title LockerFactory
/// @author velodrome.finance
/// @notice Manages creating locker instances
abstract contract LockerFactory is ILockerFactory, Ownable, ReentrancyGuardTransient {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @inheritdoc ILockerFactory
    uint256 public constant MAX_BPS = 10_000;

    /// @inheritdoc ILockerFactory
    address public immutable voter;
    /// @inheritdoc ILockerFactory
    address public immutable poolLauncher;
    /// @inheritdoc ILockerFactory
    address public immutable lockerImplementation;
    /// @inheritdoc ILockerFactory
    PoolType public immutable poolType;
    /// @inheritdoc ILockerFactory
    address public newLockerFactory;

    /// @inheritdoc ILockerFactory
    mapping(address _locker => bool) public instances;

    /// @dev Mapping from pool to set of lockers (all lockers for a specific pool)
    mapping(address _pool => EnumerableSet.AddressSet) internal _lockers;
    /// @dev Mapping from owner to set of lockers (all lockers owned by a user)
    mapping(address _owner => EnumerableSet.AddressSet) internal _lockersPerUser;
    /// @dev Mapping from pool to owner to set of lockers (all lockers in a pool owned by a user)
    mapping(address _pool => mapping(address _owner => EnumerableSet.AddressSet)) internal _lockersPerPoolPerUser;

    constructor(
        address _owner,
        address _poolLauncher,
        address _lockerImplementation,
        address _voter,
        PoolType _poolType
    ) Ownable(_owner) {
        poolLauncher = _poolLauncher;
        lockerImplementation = _lockerImplementation;
        voter = _voter;
        poolType = _poolType;
    }

    /// @inheritdoc ILockerFactory
    function unlock(address _locker, address _recipient) external nonReentrant {
        if (_recipient == address(0)) revert ZeroAddress();
        if (!instances[_locker]) revert NotLocker();
        address _owner = Ownable(_locker).owner();
        if (msg.sender != _owner) revert NotLockerOwner();
        if (block.timestamp < ILocker(_locker).lockedUntil()) revert Locked();
        if (ILocker(_locker).staked()) revert Staked();

        _unlockLP({
            _locker: _locker,
            _pool: ILocker(_locker).pool(),
            _recipient: _recipient,
            _refundAddress: _recipient,
            _owner: _owner
        });
    }

    /// @inheritdoc ILockerFactory
    function migrate(
        address _locker,
        uint256 _unlock0Min,
        uint256 _unlock1Min,
        uint256 _amount0Min,
        uint256 _amount1Min
    ) external virtual returns (uint256, uint256, address);

    /// @inheritdoc ILockerFactory
    function setNewLockerFactory(address _lockerFactory) external onlyOwner nonReentrant {
        if (_lockerFactory == address(0)) revert ZeroAddress();
        newLockerFactory = _lockerFactory;

        emit NewLockerFactorySet({lockerFactory: _lockerFactory});
    }

    /// @inheritdoc ILockerFactory
    function transferLockerOwnership(address _owner, address _newOwner, address _pool) external {
        if (!instances[msg.sender]) revert NotLocker();

        //slither-disable-next-line unused-return
        _lockersPerUser[_owner].remove(msg.sender);
        //slither-disable-next-line unused-return
        _lockersPerPoolPerUser[_pool][_owner].remove(msg.sender);

        //slither-disable-next-line unused-return
        _lockersPerUser[_newOwner].add(msg.sender);
        //slither-disable-next-line unused-return
        _lockersPerPoolPerUser[_pool][_newOwner].add(msg.sender);
    }

    /// @inheritdoc ILockerFactory
    function locked(address _pool) external view returns (uint256) {
        //slither-disable-next-line uninitialized-local
        uint256 liquidity;
        uint256 length = _lockers[_pool].length();
        address[] memory cachedLockers = _lockers[_pool].values();
        for (uint256 i = 0; i < length; i++) {
            liquidity += _liquidity(cachedLockers[i]);
        }
        return liquidity;
    }

    /// @inheritdoc ILockerFactory
    function locked(address _pool, uint256 _start, uint256 _end) external view returns (uint256) {
        //slither-disable-next-line uninitialized-local
        uint256 liquidity;
        uint256 length = _lockers[_pool].length();
        _end = _end < length ? _end : length;
        address[] memory cachedLockers = _lockers[_pool].values();
        for (uint256 i = 0; i < _end - _start; i++) {
            liquidity += _liquidity(cachedLockers[i + _start]);
        }
        return liquidity;
    }

    /// @inheritdoc ILockerFactory
    function locks(address _pool) external view returns (uint256) {
        return _lockers[_pool].length();
    }

    /// @inheritdoc ILockerFactory
    function lockers(address _pool) external view returns (address[] memory) {
        return _lockers[_pool].values();
    }

    /// @inheritdoc ILockerFactory
    function lockers(address _pool, uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = _lockers[_pool].length();
        _end = _end < length ? _end : length;
        address[] memory lockers_ = new address[](_end - _start);
        address[] memory cachedLockers = _lockers[_pool].values();
        for (uint256 i = 0; i < _end - _start; i++) {
            lockers_[i] = cachedLockers[i + _start];
        }
        return lockers_;
    }

    /// @inheritdoc ILockerFactory
    function lockersCount(address _pool) external view returns (uint256) {
        return _lockers[_pool].length();
    }

    /// @inheritdoc ILockerFactory
    function lockersPerUser(address _user) external view returns (address[] memory) {
        return _lockersPerUser[_user].values();
    }

    /// @inheritdoc ILockerFactory
    function lockersPerUser(address _user, uint256 _start, uint256 _end) external view returns (address[] memory) {
        uint256 length = _lockersPerUser[_user].length();
        _end = _end < length ? _end : length;
        address[] memory lockers_ = new address[](_end - _start);
        address[] memory cachedLockers = _lockersPerUser[_user].values();
        for (uint256 i = 0; i < _end - _start; i++) {
            lockers_[i] = cachedLockers[i + _start];
        }
        return lockers_;
    }

    /// @inheritdoc ILockerFactory
    function lockersPerUserCount(address _user) external view returns (uint256) {
        return _lockersPerUser[_user].length();
    }

    /// @inheritdoc ILockerFactory
    function lockersPerPoolPerUser(address _pool, address _user) external view returns (address[] memory) {
        return _lockersPerPoolPerUser[_pool][_user].values();
    }

    /// @inheritdoc ILockerFactory
    function lockersPerPoolPerUser(address _pool, address _user, uint256 _start, uint256 _end)
        external
        view
        returns (address[] memory)
    {
        uint256 length = _lockersPerPoolPerUser[_pool][_user].length();
        _end = _end < length ? _end : length;
        address[] memory lockers_ = new address[](_end - _start);
        address[] memory cachedLockers = _lockersPerPoolPerUser[_pool][_user].values();
        for (uint256 i = 0; i < _end - _start; i++) {
            lockers_[i] = cachedLockers[i + _start];
        }
        return lockers_;
    }

    /// @inheritdoc ILockerFactory
    function lockersPerPoolPerUserCount(address _pool, address _user) external view returns (uint256) {
        return _lockersPerPoolPerUser[_pool][_user].length();
    }

    /**
     * @notice Unlocks the underlying LP from a given Locker
     * @param _locker The locker to be unlocked
     * @param _pool The underlying pool for the locker
     * @param _recipient The recipient for the unlocked LP
     * @param _refundAddress _refundAddress The address to receive any leftover tokens from the locker
     * @param _owner The owner of the locker
     */
    function _unlockLP(address _locker, address _pool, address _recipient, address _refundAddress, address _owner)
        internal
    {
        _removeLocker({_locker: _locker, _pool: _pool, _lockerOwner: _owner});

        //slither-disable-next-line unused-return
        ILocker(_locker).unlock({_recipient: _recipient, _refundAddress: _refundAddress});
        emit LockerUnlocked({
            locker: _locker,
            underlyingPool: _pool,
            recipient: _recipient,
            refundAddress: _refundAddress
        });
    }

    function _addLocker(address _locker, address _pool, address _lockerOwner) internal {
        instances[_locker] = true;
        //slither-disable-next-line unused-return
        _lockers[_pool].add(_locker);
        //slither-disable-next-line unused-return
        _lockersPerUser[_lockerOwner].add(_locker);
        //slither-disable-next-line unused-return
        _lockersPerPoolPerUser[_pool][_lockerOwner].add(_locker);
    }

    function _removeLocker(address _locker, address _pool, address _lockerOwner) internal {
        delete instances[_locker];
        //slither-disable-next-line unused-return
        _lockers[_pool].remove(_locker);
        //slither-disable-next-line unused-return
        _lockersPerUser[_lockerOwner].remove(_locker);
        //slither-disable-next-line unused-return
        _lockersPerPoolPerUser[_pool][_lockerOwner].remove(_locker);
    }

    function _liquidity(address _locker) internal view virtual returns (uint256);
}
