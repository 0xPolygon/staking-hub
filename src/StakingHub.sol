// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {SlashingManager} from "./staking-layer/SlashingManager.sol";
import {LockerSettings} from "./interface/IStakingHub.sol";
import {PackedUints} from "./lib/PackedUints.sol";

contract StakingHub is SlashingManager {
    using PackedUints for uint256;

    uint256 constant SERVICE_UNSUB_GAS = 500_000;

    function registerLocker() external returns (uint256 id) {
        return _setLocker(msg.sender);
    }

    function registerService(LockerSettings[] calldata lockers, uint40 unsubNotice, address slasher) external returns (uint256 id) {
        require(slasher != address(0), "Invalid slasher");

        (uint256[] memory lockerIds, uint256 slashingPercentages) = _formatLockers(lockers);
        id = _setService(msg.sender, lockerIds, slashingPercentages, unsubNotice);
        _setSlasher(id, slasher);
    }

    function subscribe(uint256 service, uint40 lockInUntil) external notFrozen {
        require(service != 0 && service <= _services.counter, "Invalid service");

        _subscribe(msg.sender, service, lockInUntil);

        uint256[] memory lockers = _lockers(service);
        uint256 slashingPercentages = _slashingPercentages(service);
        uint256 len = lockers.length;
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onSubscribe(msg.sender, service, slashingPercentages.get(i));
        }
        _service(service).onSubscribe(msg.sender, lockInUntil);
    }

    function initiateUnsubscribe(uint256 service) external notFrozen returns (uint40 unsubscribableFrom) {
        unsubscribableFrom = _initiateUnsubscription(msg.sender, service);

        if (_isLockedIn(msg.sender, service) && !_slasherUpdateScheduled(service)) {
            _service(service).onInitiateUnsubscribe(msg.sender);
        } else {
            try _service(service).onInitiateUnsubscribe{gas: SERVICE_UNSUB_GAS}(msg.sender) {}
            catch (bytes memory revertData) {
                emit UnsubscriptionInitializationWarning(service, msg.sender, revertData);
            }
        }
    }

    function finalizeUnsubscribe(uint256 service) external notFrozen {
        _unsubscribe(msg.sender, service, false);

        _notifyServiceOnUnsub(msg.sender, service);
        _notifyLockersOnUnsub(msg.sender, service);
    }

    function terminate(address staker) external {
        uint256 service = _serviceId(msg.sender);

        _unsubscribe(staker, service, true);

        _notifyLockersOnUnsub(staker, service);
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
        return _slash(staker, msg.sender, percentages);
    }

    function isFrozen(address staker) external view returns (bool) {
        return _isFrozen(staker);
    }

    function _notifyServiceOnUnsub(address staker, uint256 service) private {
        try _service(service).onFinalizeUnsubscribe{gas: SERVICE_UNSUB_GAS}(staker) {}
        catch (bytes memory revertData) {
            emit UnsubscriptionFinalizationWarning(service, staker, revertData);
        }
    }

    function _notifyLockersOnUnsub(address staker, uint256 service) private {
        uint256[] memory lockers = _lockers(service);
        uint256 len = lockers.length;

        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onUnsubscribe(staker, service, _slashingPercentages(service).get(i));
        }
    }
}
