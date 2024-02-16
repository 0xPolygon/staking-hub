// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LockerBase} from "../template/LockerBase.sol";

/// @title ERC20Locker
/// @author Polygon Labs
/// @notice An ERC20-compatible abstract template contract inheriting from BaseLocker
contract ERC20Locker is LockerBase {
    IERC20 internal immutable underlying;
    address internal immutable _burnAddress;

    mapping(address staker => uint256 balance) internal _balances;
    uint256 internal _globalTotalSupply;
    mapping(uint256 serviceId => uint256 supply) internal _serviceSupplies;

    constructor(address _underlying, address stakingHub, address burnAddress) LockerBase(stakingHub) {
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

        uint256[] memory services = getServices(user);
        uint256 len = services.length;
        for (uint256 i; i < len; ++i) {
            _serviceSupplies[services[i]] += amount;
        }

        underlying.transferFrom(msg.sender, address(this), amount);

        emit BalanceChanged(msg.sender, _balances[msg.sender]);
    }

    /// @notice amount is immediately subtracted, so that stakers cannot use it in subscriptions anymore
    /// @notice amount can still be slashed during the withdrawal delay though (_slashPendingWithdrawal)
    function initiateWithdrawal(uint256 amount) external {
        require(!_stakingHub.isFrozen(msg.sender), "Staker is frozen");
        require(amount <= _balances[msg.sender], "Insufficient balance");

        _registerWithdrawal(msg.sender, amount);

        _balances[msg.sender] -= amount;
        _globalTotalSupply -= amount;

        uint256[] memory services = getServices(msg.sender);
        uint256 len = services.length;
        for (uint256 i; i < len; ++i) {
            _serviceSupplies[services[i]] -= amount;
        }

        emit BalanceChanged(msg.sender, _balances[msg.sender]);
    }

    /// @notice amount is transferred to staker (if not slashed in the meantime)
    /// @notice no _balances adjustment is made, as already subtracted in initiateWithdrawal
    function finalizeWithdrawal() external returns (uint256 amount) {
        require(!_stakingHub.isFrozen(msg.sender), "Staker is frozen");

        amount = _finalizeWithdrawal(msg.sender);
        underlying.transfer(msg.sender, amount);

        emit WithdrawalFinalized(msg.sender, amount);
    }

    function _onSlash(address staker, uint256, uint256 amount) internal virtual override {
        uint256 remainder = _slashPendingWithdrawal(staker, amount);

        if (remainder != 0) {
            _balances[msg.sender] -= remainder;
            _globalTotalSupply -= remainder;

            uint256[] memory services = getServices(msg.sender);
            uint256 len = services.length;
            for (uint256 i; i < len; ++i) {
                _serviceSupplies[services[i]] -= remainder;
            }
        }
        underlying.transfer(_burnAddress, amount);

        emit BalanceChanged(msg.sender, _balances[msg.sender]);
    }

    function _balanceOf(address staker) internal view virtual override returns (uint256 balance) {
        return _balances[staker];
    }

    function _balanceOf(address staker, uint256 serviceId) internal view virtual override returns (uint256 balance) {
        return isSubscribed(staker, serviceId) ? _balances[staker] : 0;
    }

    function _totalSupply() internal view virtual override returns (uint256 totalSupply) {
        return _globalTotalSupply;
    }

    function _totalSupply(uint256 serviceId) internal view virtual override returns (uint256 totalSupply) {
        return _serviceSupplies[serviceId];
    }

    function _votingPowerOf(address staker) internal view virtual override returns (uint256 votingPower) {
        return _balances[staker];
    }

    function _votingPowerOf(address staker, uint256 service) internal view virtual override returns (uint256 votingPower) {
        return isSubscribed(staker, service) ? _balances[staker] : 0;
    }

    function _totalVotingPower() internal view virtual override returns (uint256 totalVotingPower) {
        return _globalTotalSupply;
    }

    function _totalVotingPower(uint256 service) internal view virtual override returns (uint256 totalVotingPower) {
        return _serviceSupplies[service];
    }
}
