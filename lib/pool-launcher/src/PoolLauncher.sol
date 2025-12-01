// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

import {IPoolLauncher} from "./interfaces/IPoolLauncher.sol";

/// @title PoolLauncher
/// @author velodrome.finance
/// @notice Manages launching pool launcher pools
abstract contract PoolLauncher is Ownable, ReentrancyGuardTransient, IPoolLauncher {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /// @inheritdoc IPoolLauncher
    address public immutable lockerFactory;
    /// @inheritdoc IPoolLauncher
    address public newPoolLauncher;

    /// @inheritdoc IPoolLauncher
    mapping(address _pool => uint256 _timestamp) public emerging;

    /// @dev tokens which can be used to pair against
    EnumerableSet.AddressSet internal _pairableTokens;
    /// @dev maps underlying pool to pool launcher pool
    mapping(address _underlyingPool => PoolLauncherPool) internal _pools;

    constructor(address _owner, address _lockerFactory) Ownable(_owner) {
        lockerFactory = _lockerFactory;
    }

    /// @inheritdoc IPoolLauncher
    function migrate(
        address _locker,
        uint256 _poolLauncherUnlockMin,
        uint256 _tokenToPairUnlockMin,
        uint256 _poolLauncherAmountMin,
        uint256 _tokenToPairAmountMin
    ) external virtual returns (PoolLauncherPool memory, address);

    /// @inheritdoc IPoolLauncher
    function setNewPoolLauncher(address _newPoolLauncher) external onlyOwner {
        if (_newPoolLauncher == address(0)) revert InvalidNewPoolLauncher();
        newPoolLauncher = _newPoolLauncher;
        emit NewPoolLauncherSet({newPoolLauncher: _newPoolLauncher});
    }

    /// @inheritdoc IPoolLauncher
    function flagEmerging(address _pool, uint256 _timestamp) external onlyOwner {
        if (_timestamp > block.timestamp) revert InvalidTimestamp();
        emerging[_pool] = _timestamp;
        emit EmergingFlagged({pool: _pool, timestamp: _timestamp});
    }

    /// @inheritdoc IPoolLauncher
    function unflagEmerging(address _pool) external onlyOwner {
        delete emerging[_pool];
        emit EmergingUnflagged({pool: _pool});
    }

    /// @inheritdoc IPoolLauncher
    function setCreationTimestamp(address _pool, uint32 _createdAt) external onlyOwner {
        if (_pool == address(0)) revert ZeroAddress();
        if (_createdAt == 0) revert ZeroTimestamp();
        if (_createdAt >= block.timestamp) revert InvalidTimestamp();

        PoolLauncherPool storage poolInfo = _pools[_pool];
        if (poolInfo.pool == address(0)) revert PoolNotInPoolLauncher();

        poolInfo.createdAt = _createdAt;
        emit CreationTimestampSet({pool: _pool, createdAt: _createdAt});
    }

    /// @inheritdoc IPoolLauncher
    function addPairableToken(address _token) external onlyOwner {
        if (_token == address(0)) revert ZeroAddress();
        if (!_pairableTokens.add({value: _token})) revert TokenAlreadyRegistered();

        emit PairableTokenAdded({token: _token});
    }

    /// @inheritdoc IPoolLauncher
    function removePairableToken(address _token) external onlyOwner {
        if (!_pairableTokens.remove({value: _token})) revert TokenNotRegistered();

        emit PairableTokenRemoved({token: _token});
    }

    /// @inheritdoc IPoolLauncher
    function pools(address _underlyingPool) external view returns (PoolLauncherPool memory) {
        return _pools[_underlyingPool];
    }

    /// @inheritdoc IPoolLauncher
    function getPairableTokensCount() external view returns (uint256) {
        return _pairableTokens.length();
    }

    /// @inheritdoc IPoolLauncher
    function getPairableTokenAt(uint256 _index) external view returns (address) {
        return _pairableTokens.at({index: _index});
    }

    /// @inheritdoc IPoolLauncher
    function isPairableToken(address _token) external view returns (bool) {
        return _pairableTokens.contains({value: _token});
    }

    /// @inheritdoc IPoolLauncher
    function getAllPairableTokens() external view returns (address[] memory) {
        return _pairableTokens.values();
    }

    /**
     * @notice Refunds any leftover tokens to a recipient
     * @dev Should be used after migrations
     * @param _token The address of the token to refund
     * @param _recipient The address to transfer tokens to
     */
    function _refundLeftover(address _token, address _recipient) internal {
        uint256 leftover = IERC20(_token).balanceOf({account: address(this)});
        if (leftover > 0) {
            IERC20(_token).safeTransfer({to: _recipient, value: leftover});
        }
    }
}
