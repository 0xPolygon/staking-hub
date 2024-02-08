// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {ServiceManager} from "./ServiceManager.sol";
import {PackedUints} from "../lib/PackedUints.sol";

struct Slasher {
    address slasher;
    address newSlasher;
    uint40 scheduledTime;
}

struct ServiceSlashingData {
    bool frozen;
    uint256 slashedPercentages;
}

struct LockerSlashes {
    uint216 latestNonce;
    uint8 percentage;
    uint8 previouslySlashed;
}

struct Slashing {
    uint40 freezeEnd;
    uint216 nonce;
    mapping(uint256 locker => LockerSlashes) totalSlashed;
    mapping(uint256 nonce => mapping(uint256 service => ServiceSlashingData)) serviceData;
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
        Slasher storage slasher = _slashers.slashers[service];
        require(slasher.slasher != newSlasher, "Same Slasher");
        require(slasher.scheduledTime == 0, "Slasher update already initiated");
        scheduledTime = uint40(block.timestamp + SLASHER_UPDATE_TIMELOCK);
        slasher.newSlasher = newSlasher;
        slasher.scheduledTime = scheduledTime;
        emit SlasherUpdateInitiated(service, newSlasher);
    }

    function _finalizeSlasherUpdate(uint256 service) internal {
        Slasher storage slasher = _slashers.slashers[service];
        uint256 scheduledTime = slasher.scheduledTime;
        require(scheduledTime != 0, "No slasher update initiated");
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
        require(!_isFrozenBy(staker, service), "Already frozen by this service");
        Slashing storage data = _slashers.data[staker];
        uint216 nonce = _getNonce(staker);
        data.nonce = nonce;
        uint40 end = uint40(block.timestamp + STAKER_FREEZE_PERIOD);
        data.freezeEnd = end;
        _slashers.data[staker].serviceData[nonce][service].frozen = true;
        emit StakerFrozen(staker, service, end);
    }

    function _slash(address staker, address slasher, uint8[] calldata percentages) internal {
        uint256 service = _slashers.services[slasher];
        require(_isSubscribed(staker, service), "Not subscribed");
        require(_isFrozenBy(staker, service), "Staker not frozen by this service");
        uint256[] memory lockers = _services.data[service].lockers;
        uint256 len = lockers.length;
        require(len == percentages.length, "Invalid number of percentages");
        uint256 maxSlashingPercentages = _services.data[service].slashingPercentages;
        uint216 nonce = _getNonce(staker);
        ServiceSlashingData storage serviceData = _slashers.data[staker].serviceData[nonce][service];
        uint256 currentSlashingPercentages = serviceData.slashedPercentages;
        for (uint256 i; i < len; ++i) {
            uint8 percentage = percentages[i];
            if (percentage == 0) continue;
            uint256 locker_ = lockers[i];
            uint8 currentPercentage = currentSlashingPercentages.get(i);
            if (currentPercentage + percentage > maxSlashingPercentages.get(i)) {
                revert("Slashing exceeds maximum");
            }
            currentSlashingPercentages.set(currentPercentage + percentage, i);
            _applySlashing(locker_, staker, percentage, nonce);
            emit StakerSlashed(staker, service, locker_, percentage);
        }
        serviceData.slashedPercentages = currentSlashingPercentages;
    }

    function _applySlashing(uint256 locker_, address staker, uint8 percentage, uint216 currentNonce) internal {
        LockerSlashes memory slashes = _slashers.data[staker].totalSlashed[locker_];
        if (currentNonce > slashes.latestNonce) {
            slashes.latestNonce = currentNonce;
            slashes.previouslySlashed = _combineSlashingPeriods(slashes.previouslySlashed, slashes.percentage);
            slashes.percentage = 0;
        }
        slashes.percentage += percentage;
        if (slashes.percentage > 100) slashes.percentage = 100;
        _slashers.data[staker].totalSlashed[locker_] = slashes;
    }

    // TODO: invariant test, can never exceed 100%
    function _slashingInfo(uint256 lockerId_, address staker) internal view returns (uint8 percentage) {
        LockerSlashes memory slashes = _slashers.data[staker].totalSlashed[lockerId_];
        percentage = _combineSlashingPeriods(slashes.previouslySlashed, slashes.percentage);
    }

    function _applySlashing(uint256 lockerId_, address staker) internal {
        LockerSlashes storage slashes = _slashers.data[staker].totalSlashed[lockerId_];
        slashes.previouslySlashed = 0;
        slashes.percentage = 0;
        // TODO: emit event
    }

    function _isFrozen(address staker) internal view returns (bool) {
        return _slashers.data[staker].freezeEnd > block.timestamp;
    }

    function _isFrozenBy(address staker, uint256 service) internal view returns (bool) {
        return _slashers.data[staker].serviceData[_getNonce(staker)][service].frozen;
    }

    function _isCommittedTo(address staker, uint256 service) internal view override returns (bool) {
        return super._isCommittedTo(staker, service) && _slashers.slashers[service].scheduledTime == 0;
    }

    function _getNonce(address staker) private view returns (uint216 nonce) {
        nonce = _slashers.data[staker].nonce;
        if (_slashers.data[staker].freezeEnd < block.timestamp) {
            nonce += 1;
        }
    }

    function _combineSlashingPeriods(uint8 oldSlashing, uint8 newSlashing) internal pure returns (uint8) {
        return oldSlashing + ((100 - oldSlashing) * newSlashing) / 100;
    }
}
