// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IV2Pool} from "../../external/IV2Pool.sol";
import {IV2Router} from "../../external/IV2Router.sol";
import {IV2LockerFactory} from "../../interfaces/extensions/v2/IV2LockerFactory.sol";
import {IV2Locker} from "../../interfaces/extensions/v2/IV2Locker.sol";
import {ILocker} from "../../interfaces/ILocker.sol";
import {Locker} from "../../Locker.sol";

/// @title V2Locker
/// @author velodrome.finance
/// @notice Manages locking liquidity, staking, and claiming rewards for V2 pools.
contract V2Locker is Locker, IV2Locker {
    using SafeERC20 for IERC20;

    /// @inheritdoc IV2Locker
    address public immutable router;

    constructor(address _factory, bool _root) Locker(_factory, _root) {
        router = IV2LockerFactory(_factory).v2Router();
    }

    /// @inheritdoc Locker
    function initialize(
        address _owner,
        address _pool,
        uint256 _lp,
        uint32 _lockedUntil,
        address _beneficiary,
        uint16 _beneficiaryShare,
        uint16 _bribeableShare
    ) external override(Locker, ILocker) initializer {
        __Locker_init({
            _owner: _owner,
            _pool: _pool,
            _lp: _lp,
            _lockedUntil: _lockedUntil,
            _beneficiary: _beneficiary,
            _beneficiaryShare: _beneficiaryShare,
            _bribeableShare: _bribeableShare
        });

        (token0, token1) = IV2Pool(pool).tokens();
    }

    /// @inheritdoc Locker
    function stake() external override(Locker, ILocker) nonReentrant onlyOwner onlyLocked ensureGauge {
        if (staked) revert AlreadyStaked();
        staked = true;

        _claimFees({_token0: token0, _token1: token1, _recipient: owner()});

        uint256 _lp = lp;
        IERC20(pool).safeIncreaseAllowance({spender: address(gauge), value: _lp});
        gauge.deposit({lp: _lp});
        emit Staked();
    }

    /// @inheritdoc Locker
    function increaseLiquidity(uint256 _amount0, uint256 _amount1, uint256 _amount0Min, uint256 _amount1Min)
        external
        override(ILocker, Locker)
        nonReentrant
        onlyOwner
        onlyLocked
        returns (uint256)
    {
        if (_amount0 == 0 && _amount1 == 0) revert ZeroAmount();

        uint256 supplied0 = _fundLocker({_token: token0, _totalBal: _amount0});
        uint256 supplied1 = _fundLocker({_token: token1, _totalBal: _amount1});

        IERC20(token0).forceApprove({spender: router, value: _amount0});
        IERC20(token1).forceApprove({spender: router, value: _amount1});

        address _pool = pool;
        (uint256 amount0Deposited, uint256 amount1Deposited, uint256 liquidity) = IV2Router(router).addLiquidity({
            tokenA: token0,
            tokenB: token1,
            stable: IV2Pool(_pool).stable(),
            amountADesired: _amount0,
            amountBDesired: _amount1,
            amountAMin: _amount0Min,
            amountBMin: _amount1Min,
            to: address(this),
            deadline: block.timestamp
        });

        IERC20(token0).forceApprove({spender: router, value: 0});
        IERC20(token1).forceApprove({spender: router, value: 0});

        _refundLeftover({_token: token0, _recipient: msg.sender, _maxAmount: supplied0});
        _refundLeftover({_token: token1, _recipient: msg.sender, _maxAmount: supplied1});

        if (staked) {
            IERC20(_pool).safeIncreaseAllowance({spender: address(gauge), value: liquidity});
            gauge.deposit({lp: liquidity});
        }

        lp += liquidity;

        emit LiquidityIncreased({amount0: amount0Deposited, amount1: amount1Deposited, liquidity: liquidity});
        return liquidity;
    }

    function _transferLP(address _recipient) internal override {
        IERC20(pool).safeTransfer({to: _recipient, value: lp});
    }

    function _collectFees(address _token0, address _token1)
        internal
        override
        returns (uint256 claimed0, uint256 claimed1)
    {
        (claimed0, claimed1) = IV2Pool(pool).claimFees();

        address _beneficiary = beneficiary;
        uint256 share0 = _deductShare({_amount: claimed0, _token: _token0, _beneficiary: _beneficiary});
        uint256 share1 = _deductShare({_amount: claimed1, _token: _token1, _beneficiary: _beneficiary});
        claimed0 -= share0;
        claimed1 -= share1;

        if (share0 > 0 || share1 > 0) {
            emit FeesClaimed({recipient: _beneficiary, claimed0: share0, claimed1: share1});
        }
    }

    function _collectRewards() internal override returns (uint256 claimed) {
        uint256 rewardsBefore = IERC20(rewardToken).balanceOf({account: address(this)});
        gauge.getReward({account: address(this)});
        uint256 rewardsAfter = IERC20(rewardToken).balanceOf({account: address(this)});

        address _beneficiary = beneficiary;
        claimed = rewardsAfter - rewardsBefore;
        uint256 share = _deductShare({_amount: claimed, _token: rewardToken, _beneficiary: _beneficiary});
        claimed -= share;

        if (share > 0) {
            emit RewardsClaimed({recipient: _beneficiary, claimed: share});
        }
    }
}
