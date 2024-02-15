// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {ServiceManager} from "./ServiceManager.sol";
import {PackedUints} from "../lib/PackedUints.sol";

struct Slasher {
    address slasher;
    address newSlasher;
    uint40 scheduledTime;
}

// Goal: REAL TIME SLASHING + AGGREGATION

// Slashers are free to implement accumulation & innocence proving if they want to save on gas.
// Per service (for this freeze period)
struct ServiceSlashingData {
    bool frozen;
    uint256 slashedPercentages; // how much it slashed in this freeze period; not cleared the nonce just moves on
}

// Per staker
struct Slashing {
    uint40 freezeStart;
    uint40 freezeEnd;
    mapping(uint256 freezeStart => mapping(uint256 service => ServiceSlashingData)) serviceData;
}

abstract contract SlashingManager is ServiceManager {
    using PackedUints for uint256;

    uint256 internal constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 internal constant STAKER_FREEZE_PERIOD = 7 days;

    struct SlashingStorage {
        mapping(uint256 service => Slasher) slashers;
        mapping(address slasher => uint256) services;
        mapping(address staker => Slashing) data;
    }

    SlashingStorage internal _slashers;

    modifier notFrozen() {
        require(!_isFrozen(msg.sender), "Staker is frozen");
        _;
    }

    function _initiateSlasherUpdate(uint256 service, address newSlasher) internal returns (uint40 scheduledTime) {
        require(newSlasher != address(0), "Invalid slasher");
        Slasher storage slasher = _slashers.slashers[service];
        require(slasher.slasher != newSlasher, "Same slasher");
        require(slasher.scheduledTime == 0, "Slasher update already initiated");
        scheduledTime = uint40(block.timestamp + SLASHER_UPDATE_TIMELOCK);
        slasher.newSlasher = newSlasher;
        slasher.scheduledTime = scheduledTime;
        emit SlasherUpdateInitiated(service, newSlasher);
    }

    function _finalizeSlasherUpdate(uint256 service) internal {
        Slasher storage slasher = _slashers.slashers[service];
        uint256 scheduledTime = slasher.scheduledTime;
        require(scheduledTime != 0, "Slasher update not initiated");
        require(block.timestamp >= slasher.scheduledTime, "Slasher cannot be updated yet");
        _setSlasher(service, slasher.newSlasher);
    }

    function _setSlasher(uint256 service, address newSlasher) internal {
        _slashers.slashers[service] = Slasher(newSlasher, address(0), 0);
        _slashers.services[newSlasher] = service;
        emit SlasherUpdated(service, newSlasher);
    }

    function _freeze(address staker, address slasher) internal {
        uint256 service = _slashers.services[slasher];
        require(_isSubscribed(staker, service), "Not subscribed");
        require(!_isFrozenBy(staker, service), "Already frozen by this service"); //.frozen == false
        uint256 end = _updateFreezePeriod(staker, service);
        emit StakerFrozen(staker, service, end);
    }

    function _updateFreezePeriod(address staker, uint256 byService) internal returns (uint40 end) {
        Slashing storage data = _slashers.data[staker];
        if (data.freezeEnd < block.timestamp) {
            data.freezeStart = uint40(block.timestamp);
        }
        data.serviceData[block.timestamp][byService].frozen = true;
        end = uint40(block.timestamp + STAKER_FREEZE_PERIOD);
        data.freezeEnd = end;
    }

    function _slash(address staker, address slasher, uint8[] calldata percentages) internal returns (uint256[] memory newBalances) {
        // get service and check that staker is subscribed and already frozen
        uint256 service = _slashers.services[slasher];
        require(_isSubscribed(staker, service), "Not subscribed");
        require(_isFrozenBy(staker, service), "Staker not frozen by this service");

        uint256[] memory lockers = _services.data[service].lockers;
        uint256 len = lockers.length;

        require(len == percentages.length, "Invalid number of percentages");

        uint256 maxSlashingPercentages = _services.data[service].slashingPercentages;
        uint40 freezeStart = _slashers.data[staker].freezeStart;
        ServiceSlashingData storage serviceData = _slashers.data[staker].serviceData[freezeStart][service];
        uint256 currentSlashingPercentages = serviceData.slashedPercentages; // slashed so far in the freeze period

        newBalances = new uint256[](len);

        for (uint256 i; i < len; ++i) {
            uint8 percentage = percentages[i];
            if (percentage == 0) continue;
            uint256 locker_ = lockers[i];
            uint8 currentPercentage = currentSlashingPercentages.get(i);

            // The service calculates the percentage on the original amount before submitting)
            if (currentPercentage + percentage > maxSlashingPercentages.get(i)) {
                // the staker's stake cannot change in the meantime
                revert("Slashing exceeds maximum");
            }

            // The cumulative of all for this period (can not exceed the max)
            currentSlashingPercentages.set(currentPercentage + percentage, i);
            newBalances[i] = locker(locker_).onSlash(staker, service, percentage, freezeStart);

            emit StakerSlashed(staker, service, locker_, percentage, newBalances[i]);
        }

        serviceData.slashedPercentages = currentSlashingPercentages;
    }

    function _isFrozen(address staker) internal view returns (bool) {
        return _slashers.data[staker].freezeEnd > block.timestamp;
    }

    function _isFrozenBy(address staker, uint256 service) internal view returns (bool) {
        uint256 freezeStart = _slashers.data[staker].freezeStart;
        return _slashers.data[staker].serviceData[freezeStart][service].frozen;
    }

    function _isLockedIn(address staker, uint256 service) internal view override returns (bool) {
        return super._isLockedIn(staker, service) && _slashers.slashers[service].scheduledTime == 0;
    }
}
