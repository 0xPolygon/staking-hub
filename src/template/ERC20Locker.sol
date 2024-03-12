// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {ILocker} from "../interface/ILocker.sol";
import {StakingHub} from "../StakingHub.sol";
import {ServiceTracker, ServiceStorage} from "../lib/ServiceTracker.sol";

abstract contract ERC20Locker is ILocker {
    using ServiceTracker for ServiceStorage;

    uint256 internal constant STAKER_WITHDRAWAL_DELAY = 7 days;

    struct SlashingData {
        uint40 freezeStart;
        uint216 totalSlashed;
        uint256 initialBalance;
    }

    struct PendingWithdrawal {
        uint40 timestamp;
        uint256 amount;
    }

    StakingHub internal _stakingHub;
    uint256 internal _id;

    mapping(address staker => SlashingData[]) internal _slashingData;
    mapping(address staker => PendingWithdrawal) pending;
    ServiceStorage internal _serviceStorage;

    function __initializeERC20Locker(address stakingHub) internal {
        _stakingHub = StakingHub(stakingHub);
    }

    function _registerLocker() internal returns (uint256 id_) {
        require(_id == 0, "Locker already registered");
        id_ = StakingHub(_stakingHub).registerLocker();
        _id = id_;
    }

    function _registerWithdrawal(address staker, uint256 amount) internal {
        PendingWithdrawal storage pendingWithdrawal = pending[staker];
        require(amount != 0, "Invalid amount");
        require(pendingWithdrawal.timestamp == 0, "Withdrawal already initiated");
        pending[staker] = PendingWithdrawal({timestamp: uint40(block.timestamp + STAKER_WITHDRAWAL_DELAY), amount: amount});
    }

    function _finalizeWithdrawal(address staker) internal returns (uint256 amount) {
        PendingWithdrawal storage pendingWithdrawal = pending[staker];
        amount = pendingWithdrawal.amount;
        require(amount != 0, "Withrawal not initiated");
        require(pendingWithdrawal.timestamp < block.timestamp, "Cannot withdraw at this time");
        delete pending[staker];
    }

    function _slashPendingWithdrawal(address staker, uint256 amount) internal returns (uint256 remainder) {
        PendingWithdrawal storage pendingWithdrawal = pending[staker];
        uint256 pendingAmount = pendingWithdrawal.amount;
        if (pendingAmount == 0) return amount;
        if (amount >= pendingAmount) {
            delete pending[staker];
            remainder = amount - pendingAmount;
        } else {
            pendingWithdrawal.amount -= amount;
            remainder = 0;
        }
    }

    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external {
        require(msg.sender == address(_stakingHub), "Unauthorized");
        _serviceStorage.addService(staker, service);
        _onSubscribe(staker, service, maxSlashPercentage);
    }

    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external {
        require(msg.sender == address(_stakingHub), "Unauthorized");
        _serviceStorage.removeService(staker, service);
        _onUnsubscribe(staker, service, maxSlashPercentage);
    }

    function onSlash(address staker, uint256 service, uint8 percentage, uint40 freezeStart) external {
        require(msg.sender == address(_stakingHub), "Unauthorized");
        SlashingData storage slashingData = _getSlashingData(staker, freezeStart);
        uint256 totalSlashed = slashingData.totalSlashed;
        if (totalSlashed == 100) return;
        if (totalSlashed + percentage > 100) {
            percentage = uint8(100 - totalSlashed);
            totalSlashed = 100;
        } else {
            totalSlashed += uint216(percentage);
        }
        uint256 amount = (slashingData.initialBalance * percentage) / 100;
        _onSlash(staker, service, amount);
    }

    function balanceOf(address staker) external view returns (uint256 balance) {
        return _balanceOf(staker);
    }

    function balanceOf(address staker, uint256 serviceId) external view returns (uint256 balance) {
        return _balanceOf(staker, serviceId);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply();
    }

    function totalSupply(uint256 serviceId) external view returns (uint256) {
        return _totalSupply(serviceId);
    }

    function votingPowerOf(address staker) external view returns (uint256 votingPower) {
        return _votingPowerOf(staker);
    }

    function votingPowerOf(address staker, uint256 service) external view returns (uint256 votingPower) {
        return _votingPowerOf(staker, service);
    }

    function totalVotingPower() external view returns (uint256) {
        return _totalVotingPower();
    }

    function totalVotingPower(uint256 service) external view returns (uint256) {
        return _totalVotingPower(service);
    }

    function id() external view returns (uint256) {
        return _id;
    }

    function services(address staker) public view returns (uint256[] memory) {
        return _serviceStorage.getServices(staker);
    }

    function isSubscribed(address staker, uint256 service) public view returns (bool) {
        return _serviceStorage.isSubscribed(staker, service);
    }

    /// @dev if a new freeze period starts, the previous period is finalized and a new one is returned
    function _getSlashingData(address staker, uint40 freezeStart) private returns (SlashingData storage) {
        uint256 len = _slashingData[staker].length;
        if (len == 0 || _slashingData[staker][len - 1].freezeStart < freezeStart) {
            _slashingData[staker].push(
                SlashingData({freezeStart: freezeStart, totalSlashed: 0, initialBalance: _balanceOf(staker) + _pendingWithdrawal(staker)})
            );
            len++;
        }
        return _slashingData[staker][len - 1];
    }

    function _pendingWithdrawal(address staker) internal view returns (uint256 amount) {
        return pending[staker].amount;
    }

    function _onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) internal virtual {}

    function _onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) internal virtual {}

    function _onSlash(address staker, uint256 service, uint256 amount) internal virtual {}

    function _balanceOf(address staker) internal view virtual returns (uint256 balance);

    function _balanceOf(address staker, uint256 serviceId) internal view virtual returns (uint256 balance);

    function _totalSupply() internal view virtual returns (uint256);

    function _totalSupply(uint256 serviceId) internal view virtual returns (uint256);

    function _votingPowerOf(address staker) internal view virtual returns (uint256 votingPower);

    function _votingPowerOf(address staker, uint256 service) internal view virtual returns (uint256 votingPower);

    function _totalVotingPower() internal view virtual returns (uint256);

    function _totalVotingPower(uint256 service) internal view virtual returns (uint256);
}
