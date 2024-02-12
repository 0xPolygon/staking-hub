// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {SlashingManager} from "./staking-layer/SlashingManager.sol";
import {SlashingInput} from "./interface/IStakingLayer.sol";
import {PackedUints} from "./lib/PackedUints.sol";

contract StakingLayer is SlashingManager {
    using PackedUints for uint256;

    function registerLocker() external returns (uint256 id) {
        return _setLocker(msg.sender);
    }

    function registerService(SlashingInput[] calldata lockers, uint40 unstakingNoticePeriod, address slasher) external returns (uint256 id) {
        require(slasher != address(0), "Invalid slasher");
        (uint256[] memory lockerIds, uint256 slashingPercentages) = _formatLockers(lockers);
        id = _setService(msg.sender, lockerIds, slashingPercentages, unstakingNoticePeriod);
        _setSlasher(id, slasher);
    }

    function subscribe(uint256 service, uint40 lockInUntil) external notFrozen {
        require(service != 0 && service <= _services.counter, "Invalid service");
        _subscribe(msg.sender, service, lockInUntil);
        uint256[] memory lockers = _lockers(service);
        uint256 slashingPercentages = _slashingPercentages(service);
        uint256 len = lockers.length;
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onSubscribe(msg.sender, service, slashingPercentages.get(i), LOCKER_RISK_MAXIMUM);
        }
    }

    function cancelSubscription(uint256 service) external notFrozen {
        _cancelSubscription(msg.sender, service);
        if (_isLockedIn(msg.sender, service)) {
            _service(service).onCancelSubscription(msg.sender);
        } else {
            try _service(service).onCancelSubscription(msg.sender) {}
            catch (bytes memory revertData) {
                emit SubscriptionCancelationWarning(service, msg.sender, revertData);
            }
        }
    }

    function unsubscribe(uint256 service) external notFrozen {
        _unsubscribe(msg.sender, service, false);
        if (_isLockedIn(msg.sender, service)) {
            _service(service).onUnsubscribe(msg.sender);
        } else {
            try _service(service).onUnsubscribe(msg.sender) {}
            catch (bytes memory revertData) {
                emit UnsubscriptionWarning(service, msg.sender, revertData);
            }
        }
        uint256[] memory lockers = _lockers(service);
        uint256 len = lockers.length;
        // Note: A service needs to trust the lockers not to revert on the call
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onUnsubscribe(msg.sender, service);
        }
    }

    function unsubscribe(address staker) external {
        require(!_isFrozen(staker), "Staker is frozen");
        uint256 service = _serviceId(msg.sender);
        _unsubscribe(staker, service, true);
        uint256[] memory lockers = _lockers(service);
        uint256 len = lockers.length;
        // Note: A service needs to trust the lockers not to revert on the call
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onUnsubscribe(msg.sender, service);
        }
    }

    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime) {
        scheduledTime = _initiateSlasherUpdate(_serviceId(msg.sender), newSlasher);
    }

    function finalizeSlasherUpdate() external {
        _finalizeSlasherUpdate(_serviceId(msg.sender));
    }

    function freeze(address staker) external {
        _freeze(staker, msg.sender);
    }

    function slash(address staker, uint8[] calldata percentages) external {
        _slash(staker, msg.sender, percentages);
    }

    function slashedPercentage(uint256 lockerId_, address staker) external view returns (uint8 percentage) {
        return _laggingSlashedPercentage(lockerId_, staker);
    }

    function totalSlashedPercentage(uint256 lockerId_) external view returns (uint8 percentage) {
        // TODO
    }

    function onBurn(address staker) external {
        _onBurn(lockerId(msg.sender), staker);
    }
}
