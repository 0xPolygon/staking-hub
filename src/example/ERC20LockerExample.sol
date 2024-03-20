// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Locker} from "../template/ERC20Locker.sol";

/// @title ERC20LockerExample
/// @author Polygon Labs
/// @notice An ERC20-compatible abstract template contract inheriting from BaseLocker
contract ERC20LockerExample is ERC20Locker {
    IERC20 internal immutable underlying;
    address internal immutable _burnAddress;

    mapping(address staker => uint256 balance) internal _balances;
    uint256 internal _globalTotalSupply;
    mapping(uint256 serviceId => uint256 stake) internal _totalStakes;

    constructor(address _underlying, address stakingHub, address burnAddress) ERC20Locker(stakingHub) {
        underlying = IERC20(_underlying);
        _burnAddress = burnAddress;
    }

    function registerLocker() external returns (uint256 id) {
        return _registerLocker();
    }

    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    function depositFor(address user, uint256 amount) external {
        _deposit(user, amount);
    }

    function _deposit(address user, uint256 amount) private {
        require(!_stakingHub.isFrozen(user), "Staker is frozen");

        _balances[user] += amount;
        _globalTotalSupply += amount;

        uint256[] memory services_ = services(user);
        uint256 len = services_.length;
        uint256 balance = _balances[msg.sender];
        for (uint256 i; i < len; ++i) {
            _totalStakes[services_[i]] += _calcStakeIncreaseForBalanceChange(balance, _allowances[user][services_[i]].allowance, amount);
        }

        underlying.transferFrom(msg.sender, address(this), amount);

        emit BalanceChanged(msg.sender, balance);
    }

    function _onSubscribe(address staker, uint256 service, uint8) internal virtual override {
        _totalStakes[service] += stakeOf(staker, service);
    }

    function _onUnsubscribe(address staker, uint256 service, uint8) internal virtual override {
        _totalStakes[service] -= stakeOf(staker, service);
    }

    /// @notice amount is immediately subtracted, so that stakers cannot use it in subscriptions anymore
    /// @notice amount can still be slashed during the withdrawal delay though (_slashPendingWithdrawal)
    function initiateWithdrawal(uint256 amount) external {
        require(!_stakingHub.isFrozen(msg.sender), "Staker is frozen");
        (, uint256 withdrawableBalance) = _reviewSubscriptions(msg.sender);
        // Enforces lock-in periods.
        require(amount <= withdrawableBalance, "Amount exceeds withdrawable balance");

        _registerWithdrawal(msg.sender, amount);

        _balances[msg.sender] -= amount;
        _globalTotalSupply -= amount;

        uint256[] memory services_ = services(msg.sender);
        uint256 len = services_.length;
        uint256 balance = _balances[msg.sender];
        for (uint256 i; i < len; ++i) {
            _totalStakes[services_[i]] -= _calcStakeDecreaseForBalanceChange(balance, _allowances[msg.sender][services_[i]].allowance, amount);
        }

        emit BalanceChanged(msg.sender, balance);
    }

    // Can be converted to use a linked list.
    function _reviewSubscriptions(address staker) internal view returns (bool lockedIn, uint256 withdrawableBalance) {
        uint256 lockedInStake;
        (uint256[] memory services_, uint256[] memory lockIns) = _getServicesAndLockIns(staker);
        for (uint256 i; i < services_.length; ++i) {
            if (block.timestamp < lockIns[i]) {
                lockedIn = true;
                uint256 balance = _balanceOf(staker);
                uint256 allowance_ = _allowances[staker][services_[i]].allowance;
                uint256 stake = _getLesser(allowance_, balance);
                if (stake > lockedInStake) lockedInStake = stake;
            }
        }
        withdrawableBalance = _balances[staker] - lockedInStake;
    }

    /// @notice amount is transferred to staker (if not slashed in the meantime)
    /// @notice no _balances adjustment is made, as already subtracted in initiateWithdrawal
    function finalizeWithdrawal() external returns (uint256 amount) {
        require(!_stakingHub.isFrozen(msg.sender), "Staker is frozen");

        amount = _finalizeWithdrawal(msg.sender);
        underlying.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function registerApproval(uint256 service, uint256 newAllowance) internal returns (bool finalized) {
        require(!_stakingHub.isFrozen(msg.sender), "Staker is frozen");
        finalized = _registerApproval(msg.sender, service, newAllowance);
        uint256 allowance_ = _allowances[msg.sender][service].allowance;
        uint256 amount = allowance_ > newAllowance ? allowance_ - newAllowance : newAllowance - allowance_;
        // If it finalized, it means the allowance was increased.
        if (finalized) _totalStakes[service] += _calcStakeIncreaseForAllowanceChange(_balances[msg.sender], allowance_, amount);
        else _totalStakes[service] -= _calcStakeDecreaseForAllowanceChange(_balances[msg.sender], allowance_, amount);
    }

    function finalizeApproval(uint256 service) internal {
        require(!_stakingHub.isFrozen(msg.sender), "Staker is frozen");
        _finalizeApproval(msg.sender, service);
    }

    function _onSlash(address staker, uint256, uint256 amount) internal virtual override {
        uint256 remainder = _slashPendingWithdrawal(staker, amount);

        if (remainder != 0) {
            _balances[msg.sender] -= remainder;
            _globalTotalSupply -= remainder;

            uint256[] memory services_ = services(msg.sender);
            uint256 len = services_.length;
            for (uint256 i; i < len; ++i) {
                _totalStakes[services_[i]] -=
                    _calcStakeDecreaseForBalanceChange(_balances[msg.sender], _allowances[msg.sender][services_[i]].allowance, remainder);
            }
        }
        underlying.transfer(_burnAddress, amount);

        emit BalanceChanged(msg.sender, _balances[msg.sender]);
    }

    function _balanceOf(address staker) internal view virtual override returns (uint256 balance) {
        return _balances[staker];
    }

    function _totalSupply() internal view virtual override returns (uint256 totalSupply) {
        return _globalTotalSupply;
    }

    function _totalStake(uint256 serviceId) internal view virtual override returns (uint256 totalSupply) {
        return _totalStakes[serviceId];
    }

    function _votingPowerOf(address staker) internal view virtual override returns (uint256 votingPower) {
        return _balances[staker];
    }

    function _votingPowerOf(address staker, uint256 service) internal view virtual override returns (uint256 votingPower) {
        return stakeOf(staker, service);
    }

    function _totalVotingPower() internal view virtual override returns (uint256 totalVotingPower) {
        return _globalTotalSupply;
    }

    function _totalVotingPower(uint256 service) internal view virtual override returns (uint256 totalVotingPower) {
        return _totalStakes[service];
    }

    function _calcStakeIncreaseForBalanceChange(uint256 balance, uint256 allowance_, uint256 amount) internal pure returns (uint256 amountToAdd) {
        if (balance >= allowance_) return 0;
        uint256 newBalance = balance + amount;
        amountToAdd = newBalance > allowance_ ? allowance_ - balance : amount;
    }

    function _calcStakeDecreaseForBalanceChange(uint256 balance, uint256 allowance_, uint256 amount) internal pure returns (uint256 amountToSub) {
        uint256 newBalance = balance - amount;
        amountToSub = newBalance >= allowance_ ? 0 : allowance_ - newBalance;
    }

    function _calcStakeIncreaseForAllowanceChange(uint256 balance, uint256 allowance_, uint256 amount) internal pure returns (uint256 amountToAdd) {
        // just invert the params
        return _calcStakeIncreaseForBalanceChange(allowance_, balance, amount);
    }

    function _calcStakeDecreaseForAllowanceChange(uint256 balance, uint256 allowance_, uint256 amount) internal pure returns (uint256 amountToSub) {
        // just invert the params
        return _calcStakeDecreaseForBalanceChange(allowance_, balance, amount);
    }
}
