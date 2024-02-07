// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {PackedUints} from "./PackedUints.sol";
import {IService} from "../interface/IService.sol";

struct SlashingInput {
    uint256 lockerId;
    uint8 percentage;
}

struct ServiceData {
    address service;
    uint256[] lockers;
    uint256 slashingPercentages;
    uint40 unstakingNoticePeriod;
    address slasher;
    address newSlasher;
    uint40 scheduledSlasherUpdate;
    mapping(address staker => Subsciption) subscriptions;
}

struct Subsciption {
    bool subscribed;
    uint40 commitUntil;
    uint40 unstakeScheduledFor;
    uint40 frozenUntil;
}

struct Staker {
    uint216 subscriptionCount;
    // TODO invariant test that frozenUntil is always >= any subscription.frozenUntil
    uint40 frozenUntil;
    uint40 freezeCount;
}

struct ServiceStorage {
    uint256 counter;
    mapping(address => uint256) ids;
    mapping(uint256 => ServiceData) data;
    mapping(address staker => Staker) stakerData;
}

library ServiceManager {
    uint256 internal constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 internal constant STAKER_FREEZE_PERIOD = 7 days;

    function registerService(ServiceStorage storage self, address service, SlashingInput[] calldata lockers, uint40 unstakingNoticePeriod, address slasher)
        internal
        returns (uint256 id)
    {
        require(self.ids[service] == 0, "Service already registered");
        // NOTE we should probably require a notice period > 0, so that a malicious staker cannot frontrun a slashing event by unstaking immediately
        require(unstakingNoticePeriod > 0, "Invalid notice period");
        _validateLockerInputs(self, lockers);

        id = ++self.counter;
        self.ids[service] = id;

        ServiceData storage data = getServiceData(self, id);
        data.service = service;
        data.unstakingNoticePeriod = unstakingNoticePeriod;
        data.slasher = slasher;

        uint256 len = lockers.length;
        uint256 slashingPercentages;
        for (uint256 i; i < len; ++i) {
            data.lockers.push(lockers[i].lockerId);
            slashingPercentages = PackedUints.set(slashingPercentages, lockers[i].percentage, i);
        }
        data.slashingPercentages = slashingPercentages;
    }

    function initiateSlasherUpdate(ServiceStorage storage self, address service, address newSlasher) internal returns (uint40 scheduledTime) {
        ServiceData storage data = getServiceData(self, service);
        require(data.slasher != newSlasher, "Same Slasher");
        require(data.scheduledSlasherUpdate == 0, "Slasher update already initiated");

        scheduledTime = uint40(block.timestamp + SLASHER_UPDATE_TIMELOCK);
        data.newSlasher = newSlasher;
        data.scheduledSlasherUpdate = scheduledTime;
    }

    function finalizeSlasherUpdate(ServiceStorage storage self, address service) internal {
        ServiceData storage data = getServiceData(self, service);
        require(block.timestamp >= data.scheduledSlasherUpdate, "Slasher cannot be updated yet");

        data.slasher = data.newSlasher;
        data.newSlasher = address(0);
        data.scheduledSlasherUpdate = 0;
    }

    function restake(ServiceStorage storage self, address staker, uint256 serviceId, uint40 commitUntil) internal {
        require(commitUntil > block.timestamp, "Invalid commitment");
        Subsciption storage subsciption = self.data[serviceId].subscriptions[staker];
        require(!subsciption.subscribed, "Already subscribed");

        subsciption.subscribed = true;
        subsciption.commitUntil = commitUntil;
        ++self.stakerData[staker].subscriptionCount;
    }

    function initiateUnstaking(ServiceStorage storage self, address staker, uint256 serviceId) internal returns (uint40 commitment) {
        Subsciption storage subsciption = getSubscription(self, serviceId, staker);
        require(!isFrozen(self, staker), "Staker frozen");
        require(subsciption.unstakeScheduledFor == 0, "Unstaking already initiated");
        ServiceData storage data = getServiceData(self, serviceId);
        subsciption.unstakeScheduledFor = uint40(block.timestamp + data.unstakingNoticePeriod);
        return subsciption.commitUntil;
    }

    function finalizeUnstake(ServiceStorage storage self, address staker, uint256 serviceId) internal returns (uint40 commitment) {
        Subsciption storage subsciption = getSubscription(self, serviceId, staker);
        require(!isFrozen(self, staker), "Staker frozen");
        require(subsciption.unstakeScheduledFor != 0, "Unstaking not initiated");
        require(block.timestamp >= subsciption.unstakeScheduledFor, "Notice period not reached");

        subsciption.subscribed = false;
        subsciption.unstakeScheduledFor = 0;
        --self.stakerData[staker].subscriptionCount;
        return subsciption.commitUntil;
    }

    function onFreeze(ServiceStorage storage self, address sender, uint256 serviceId, address staker) internal {
        require(sender == getServiceData(self, serviceId).slasher, "Only Slasher can freeze");
        // check if the caller is subscribed
        Subsciption storage subscription = getSubscription(self, serviceId, staker);
        require(subscription.frozenUntil < block.timestamp, "Already frozen by this service");
        uint40 unfreezeTimestamp = uint40(block.timestamp + STAKER_FREEZE_PERIOD);
        subscription.frozenUntil = unfreezeTimestamp;
        ++self.stakerData[staker].freezeCount;
        self.stakerData[staker].frozenUntil = unfreezeTimestamp;
    }

    function getServiceId(ServiceStorage storage self, address service) internal view returns (uint256 id) {
        id = self.ids[service];
        if (id == 0) revert("Service does not exist");
    }

    function getServiceData(ServiceStorage storage self, address service) internal view returns (ServiceData storage data) {
        uint256 id = getServiceId(self, service);
        data = self.data[id];
    }

    function getServiceData(ServiceStorage storage self, uint256 id) internal view returns (ServiceData storage data) {
        if (id > self.counter) revert("Invalid Service");
        data = self.data[id];
    }

    function getService(ServiceStorage storage self, uint256 id) internal view returns (IService service) {
        service = IService(self.data[id].service);
    }

    function getSubscription(ServiceStorage storage self, uint256 id, address staker) internal view returns (Subsciption storage subsciption) {
        subsciption = self.data[id].subscriptions[staker];
        if (!subsciption.subscribed) revert("Not subscribed");
    }

    function isFrozen(ServiceStorage storage self, address staker) internal view returns (bool) {
        return self.stakerData[staker].frozenUntil > block.timestamp;
    }

    /// @dev Reverts if a Locker does not exist, or a duplicate is found.
    /// @dev locker ids must be sorted in ascending order for duplicate check
    function _validateLockerInputs(ServiceStorage storage self, SlashingInput[] calldata lockers_) private view {
        uint256 len = lockers_.length;
        if (len == 0 || len > 32) revert("Invalid number of lockers");
        uint256 lastId;
        for (uint256 i = 0; i < len; ++i) {
            uint256 lockerId = lockers_[i].lockerId;
            require(lockerId > lastId, "Duplicate Locker or Unsorted List");
            require(lockers_[i].percentage < 101, "Invalid slashing percentage");
        }
        require(lastId <= self.counter, "Invalid Locker");
    }
}
