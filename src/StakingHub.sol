// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {SlashingManager} from "./staking-layer/SlashingManager.sol";
import {LockerSettings} from "./interface/IStakingHub.sol";
import {PackedUints} from "./lib/PackedUints.sol";

contract StakingHub is SlashingManager {
    using PackedUints for uint256;

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
        _service(service).onSubscribe(msg.sender);
    }

    function initiateUnsubscribe(uint256 service) external notFrozen returns (uint40 unsubscribableFrom) {
        unsubscribableFrom = _initiateUnsubscribe(msg.sender, service);

        if (_isLockedIn(msg.sender, service)) {
            _service(service).onInitiateUnsubscribe(msg.sender);
        } else {
            try _service(service).onInitiateUnsubscribe(msg.sender) {}
            catch (bytes memory revertData) {
                emit InitiatedUnsubscribeWarning(service, msg.sender, revertData);
            }
        }
    }

    function finalizeUnsubscribe(uint256 service) external notFrozen {
        _finalizeUnsubscribe(msg.sender, service, false);

        _unsubscribe(msg.sender, service);
    }

    function terminate(address staker) external {
        uint256 service = _serviceId(msg.sender);

        _finalizeUnsubscribe(staker, service, true);

        _unsubscribe(staker, service);
    }

    function _unsubscribe(address staker, uint256 service) private {
        if (_isLockedIn(staker, service)) {
            _service(service).onFinalizeUnsubscribe(staker);
        } else {
            try _service(service).onFinalizeUnsubscribe(staker) {}
            catch (bytes memory revertData) {
                emit FinalizedUnsubscribeWarning(service, staker, revertData);
            }
        }

        uint256[] memory lockers = _lockers(service);
        uint256 len = lockers.length;

        // Note: A service needs to trust the lockers not to revert on the call
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onUnsubscribe(staker, service, _slashingPercentages(service).get(i));
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
        return _slash(staker, msg.sender, percentages);
    }

    function isFrozen(address staker) external view returns (bool) {
        return _isFrozen(staker);
    }
}
