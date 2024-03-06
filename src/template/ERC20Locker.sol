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
        uint256 totalSlashed;
        uint256 initialBalance;
    }

    struct PendingWithdrawal {
        uint40 timestamp;
        uint256 amount;
    }

    StakingHub internal immutable _stakingHub;
    uint256 internal _id;

    mapping(address staker => SlashingData[]) internal _slashingData;
    mapping(address staker => PendingWithdrawal) pending;
    ServiceStorage internal _serviceStorage;

    constructor(address stakingHub) {
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
        require(pendingWithdrawal.timestamp > block.timestamp, "Cannot withdraw at this time");
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

    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage, uint256 lockedInUntil) external {
        require(msg.sender == address(_stakingHub), "Unauthorized");
        _serviceStorage.addService(staker, service, lockedInUntil);
        _allowances[staker][service].allowance = type(uint256).max;
        _onSubscribe(staker, service, maxSlashPercentage);
    }

    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external {
        require(msg.sender == address(_stakingHub), "Unauthorized");
        _serviceStorage.removeService(staker, service);
        _allowances[staker][service].allowance = 0;
        _allowances[staker][service].scheduledTime = 0;
        _onUnsubscribe(staker, service, maxSlashPercentage);
    }

    function onSlash(address staker, uint256 service, uint8 percentage, uint40 freezeStart) external {
        require(msg.sender == address(_stakingHub), "Unauthorized");
        SlashingData storage slashingData = _getSlashingData(staker, freezeStart);
        uint256 initialBalance = slashingData.initialBalance;
        uint256 totalSlashed = slashingData.totalSlashed;
        uint256 slashAmount = (_getLower(_allowances[staker][service].allowance, initialBalance) * percentage) / 100;
        if (totalSlashed + slashAmount > initialBalance) {
            slashAmount = initialBalance - totalSlashed;
            if (slashAmount == 0) return;
            totalSlashed = initialBalance;
        } else {
            totalSlashed += slashAmount;
        }
        slashingData.totalSlashed = totalSlashed;
        _onSlash(staker, service, slashAmount);
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

    function _onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) internal virtual;

    function _onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) internal virtual;

    function _onSlash(address staker, uint256 service, uint256 amount) internal virtual;

    function _balanceOf(address staker) internal view virtual returns (uint256 balance);

    function _balanceOf(address staker, uint256 serviceId) internal view virtual returns (uint256 balance);

    function _totalSupply() internal view virtual returns (uint256);

    function _totalSupply(uint256 serviceId) internal view virtual returns (uint256);

    function _votingPowerOf(address staker) internal view virtual returns (uint256 votingPower);

    function _votingPowerOf(address staker, uint256 service) internal view virtual returns (uint256 votingPower);

    function _totalVotingPower() internal view virtual returns (uint256);

    function _totalVotingPower(uint256 service) internal view virtual returns (uint256);

    // PARTIAL RESTAKING VIA APPROAVALS

    struct Allowance {
        uint256 allowance;
        uint256 scheduledAllowance;
        uint256 scheduledTime;
    }

    mapping(address staker => mapping(uint256 service => Allowance)) _allowances;

    function _registerApproval(address staker, uint256 service, uint256 newAllowance) internal returns (bool finalized) {
        Allowance memory allowanceData = _allowances[staker][service];
        require(allowanceData.scheduledTime == 0, "Already registered");
        require(allowanceData.allowance != newAllowance, "No change");
        bool decreasing = newAllowance < allowanceData.allowance;
        if (decreasing) {
            require(newAllowance < _allowances[staker][service].allowance, "Cannot decrease while locked-in");
        }

        _allowances[staker][service].scheduledAllowance = newAllowance;
        _allowances[staker][service].scheduledTime = block.timestamp + (decreasing ? STAKER_WITHDRAWAL_DELAY : 0);

        // Note: Security consideration - The service should assume the staker will finalize the approval if the allowance is supposed to DECREASE.
        emit AllowanceChanged(staker, service, newAllowance);

        if (!decreasing) {
            _finalizeApproval(staker, service);
            finalized = true;
        }
    }

    function _finalizeApproval(address staker, uint256 service) internal {
        Allowance memory allowanceData = _allowances[staker][service];
        require(allowanceData.scheduledTime != 0, "Not registered");

        _allowances[staker][service].allowance = allowanceData.scheduledAllowance;
        _allowances[staker][service].scheduledTime = 0;

        emit Approved(staker, service, allowanceData.scheduledAllowance);
    }

    // FOR EXTERNAL USE, MAINLY. ONLY USE INTERNALLY IF YOU KNOW WHAT YOU'RE DOING!
    function allowance(address staker, uint256 service) public view returns (uint256 amount) {
        Allowance memory allowanceData = _allowances[staker][service];
        uint256 currentAllowance = allowanceData.allowance;
        uint256 newAllowance = allowanceData.scheduledAllowance;
        // If nothing scheduled, return the allowance.
        if (allowanceData.scheduledTime == 0) return currentAllowance;
        // If something scheduled, return the new allowance if it's going to decrease, or the current allowance if it's going to increase.
        return newAllowance < currentAllowance ? newAllowance : currentAllowance;
    }

    // FOR EXTERNAL USE, MAINLY. ONLY USE INTERNALLY IF YOU KNOW WHAT YOU'RE DOING!
    function stakeOf(address staker, uint256 service) public view returns (uint256 stake) {
        uint256 balance = _balanceOf(staker); // taken out immediately (^) but remians slashable (*)
        // uint256 allowance_ = _allowances[staker][service].allowance; // actual (*) but report the future one (^)
        // so, when they ask what's the balance, they get what it will be
        // when they ask what's the allowance, they get what it will be
        // they should slash based on percentages, so the actual balance doesn't matter
        // they SHOULD assume any allowance decrease will be finalized, and only care about the reported (future) allowance
        // ... since they should slashed based on percentages and not amounts, the actual allowance doesn't matter
        // btw when i say should slash based on percentages, i mean that the punishment A should be x%, not a static amount y.
        // we track balances and allowances a bit differently - we need to sum the balance and withdrawal, but only read allowance, when working with them.
        // so, what should we do here? this reports how much a staker has staked in a service
        // total stakes for services are tracked on init withdrawal/approval when the balance tracking is updated, but allowance tracking is updated only if increasing, not decreasing
        // therefore, we should use the future allowance, which we can get from the public getter
        uint256 allowance_ = allowance(staker, service);
        return _getLower(allowance_, balance);
    }

    function _getLower(uint256 a, uint256 b) internal pure returns (uint256 lower) {
        return a <= b ? a : b;
    }

    function _getServicesAndLockIns(address staker) internal view returns (uint256[] memory services_, uint256[] memory lockIns) {
        return _serviceStorage.getServicesAndLockIns(staker);
    }
}
