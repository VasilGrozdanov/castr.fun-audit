// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19 <0.9.0;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IGauge} from "../../external/IGauge.sol";
import {INonfungiblePositionManager as INfpm} from "../../external/INonfungiblePositionManager.sol";
import {ICLLockerFactory} from "../../interfaces/extensions/cl/ICLLockerFactory.sol";
import {ICLLocker} from "../../interfaces/extensions/cl/ICLLocker.sol";
import {ILocker} from "../../interfaces/ILocker.sol";
import {Locker} from "../../Locker.sol";

/// @title CLLocker
/// @author velodrome.finance
/// @notice Manages locking liquidity, staking, and claiming rewards for concentrated liquidity pools.
contract CLLocker is Locker, ICLLocker, IERC721Receiver {
    using SafeERC20 for IERC20;

    /// @inheritdoc ICLLocker
    INfpm public immutable nfpManager;

    constructor(address _factory, bool _root) Locker(_factory, _root) {
        nfpManager = ICLLockerFactory(_factory).nfpManager();
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

        //slither-disable-next-line unused-return
        (,, token0, token1,,,,,,,,) = nfpManager.positions({tokenId: _lp});
    }

    /// @inheritdoc Locker
    function stake() external override(Locker, ILocker) nonReentrant onlyOwner onlyLocked ensureGauge {
        if (staked) revert AlreadyStaked();
        staked = true;

        _claimFees({_token0: token0, _token1: token1, _recipient: owner()});

        uint256 _lp = lp;
        nfpManager.approve({to: address(gauge), tokenId: _lp});
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

        (address _token0, address _token1) = (token0, token1);
        uint256 supplied0 = _fundLocker({_token: _token0, _totalBal: _amount0});
        uint256 supplied1 = _fundLocker({_token: _token1, _totalBal: _amount1});

        if (staked) {
            _claimRewards({_recipient: msg.sender});
            IGauge(gauge).withdraw({lp: lp});
        }

        IERC20(_token0).safeIncreaseAllowance({spender: address(nfpManager), value: _amount0});
        IERC20(_token1).safeIncreaseAllowance({spender: address(nfpManager), value: _amount1});

        (uint128 liquidity, uint256 amount0, uint256 amount1) = nfpManager.increaseLiquidity(
            INfpm.IncreaseLiquidityParams({
                tokenId: lp,
                amount0Desired: _amount0,
                amount1Desired: _amount1,
                amount0Min: _amount0Min,
                amount1Min: _amount1Min,
                deadline: block.timestamp
            })
        );

        _refundLeftover({_token: _token0, _recipient: msg.sender, _maxAmount: supplied0});
        _refundLeftover({_token: _token1, _recipient: msg.sender, _maxAmount: supplied1});

        if (staked) {
            nfpManager.approve({to: address(gauge), tokenId: lp});
            gauge.deposit({lp: lp});
        }

        IERC20(_token0).forceApprove({spender: address(nfpManager), value: 0});
        IERC20(_token1).forceApprove({spender: address(nfpManager), value: 0});

        emit LiquidityIncreased({amount0: amount0, amount1: amount1, liquidity: uint256(liquidity)});
        return uint256(liquidity);
    }

    function _transferLP(address _recipient) internal override {
        nfpManager.safeTransferFrom({from: address(this), to: _recipient, tokenId: lp});
    }

    function _collectFees(address _token0, address _token1)
        internal
        override
        returns (uint256 claimed0, uint256 claimed1)
    {
        (claimed0, claimed1) = nfpManager.collect({
            params: INfpm.CollectParams({
                tokenId: lp,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        });

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
        gauge.getReward({tokenId: lp});
        uint256 rewardsAfter = IERC20(rewardToken).balanceOf({account: address(this)});

        address _beneficiary = beneficiary;
        claimed = rewardsAfter - rewardsBefore;
        uint256 share = _deductShare({_amount: claimed, _token: rewardToken, _beneficiary: _beneficiary});
        claimed -= share;

        if (share > 0) {
            emit RewardsClaimed({recipient: _beneficiary, claimed: share});
        }
    }

    /// @inheritdoc IERC721Receiver
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
