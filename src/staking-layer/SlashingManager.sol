// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {ServiceManager} from "./ServiceManager.sol";
import {PackedUints} from "../lib/PackedUints.sol";

struct Slasher {
    address slasher;
    address newSlasher;
    uint40 scheduledTime;
}

// Per service (for this freeze period)
struct ServiceSlashingData {
    bool frozen;
    uint256 slashedPercentages; // how much it slashed in this freeze period; not cleared the nonce just moves on
}

struct LockerSlashes {
    uint216 latestNonce;
    uint8 percentage; // for this locker for this freeze period
    uint8 previouslySlashed; // for prev periods
}

// Per staker
struct Slashing {
    uint40 freezeEnd;
    uint216 nonce; // Represents a freeze period
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
        require(!_isFrozenBy(staker, service), "Already frozen by this service");
        Slashing storage data = _slashers.data[staker];
        uint216 nonce = _getNonce(staker);
        data.nonce = nonce; // the nonce gets updated on freezing
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
        uint256 currentSlashingPercentages = serviceData.slashedPercentages; // slashed so far in the freeze period
        for (uint256 i; i < len; ++i) {
            uint8 percentage = percentages[i];
            if (percentage == 0) continue;
            uint256 locker_ = lockers[i];
            uint8 currentPercentage = currentSlashingPercentages.get(i);
            // For this freeze period? Yes. (the service calculates the percentage on the original amount before submitting)
            if (currentPercentage + percentage > maxSlashingPercentages.get(i)) {
                // the staker's stake cannot change in the meantime
                revert("Slashing exceeds maximum");
            }
            // The cumulative of all for this period (can not exceed the max)
            currentSlashingPercentages.set(currentPercentage + percentage, i);
            _updatePerLockerData(locker_, staker, percentage, nonce);
            emit StakerSlashed(staker, service, locker_, percentage);
        }
        serviceData.slashedPercentages = currentSlashingPercentages;
    }

    // for diff services (PER locker)
    function _updatePerLockerData(uint256 locker_, address staker, uint8 percentage, uint216 currentNonce) internal {
        LockerSlashes memory slashes = _slashers.data[staker].totalSlashed[locker_];
        // new period
        if (currentNonce > slashes.latestNonce) {
            slashes.latestNonce = currentNonce;
            slashes.previouslySlashed = _combineSlashingPeriods(slashes.previouslySlashed, slashes.percentage);
            slashes.percentage = 0;
        }
        slashes.percentage += percentage;
        if (slashes.percentage > 100) slashes.percentage = 100;
        _slashers.data[staker].totalSlashed[locker_] = slashes;
    }

    // N    staker nonce
    // n    per-locker-data-updated-at nonce
    // c    percentage per locker for current freeze period
    // t    percentage per locker for previous freeze periods

    // N n   c    t
    // 0 0   0    0
    // freeze                   (N up)
    // 1 0   0    0
    // slash                    (n up, consolidate t c, add c)
    // 1 1 665    0
    // slash                    (add c)
    // 1 1 666    0
    // *period ends*
    // freeze                   (N up)
    // 2 1 666    0
    // slash                    (n up, consolidate t c, add c)
    // 2 2 333  666
    // slash                    (add c)
    // 2 2 334  666
    // *period ends*

    // info:
    //  not frozen?
    //      just consolidate t
    //  frozen? N went up
    //      check if t consolidated
    //          n == N
    //              ret t
    //          n != N
    //              consolidate t

    function _laggingSlashedPercentage(uint256 lockerId_, address staker) internal view returns (uint8 percentage) {
        LockerSlashes memory slashes = _slashers.data[staker].totalSlashed[lockerId_];
        if (!_isFrozen(staker)) {
            percentage = _combineSlashingPeriods(slashes.previouslySlashed, slashes.percentage);
        } else {
            if (slashes.latestNonce == _slashers.data[staker].nonce) {
                percentage = slashes.previouslySlashed;
            } else {
                percentage = _combineSlashingPeriods(slashes.previouslySlashed, slashes.percentage);
            }
        }
    }

    ///@dev You will almost always need the lagging percentage, not the coincident one. Only use if you know what you're doing.
    function _coincidentSlashedPercentage(uint256 lockerId_, address staker) internal view returns (uint8 percentage) {
        LockerSlashes memory slashes = _slashers.data[staker].totalSlashed[lockerId_];
        percentage = _combineSlashingPeriods(slashes.previouslySlashed, slashes.percentage);
    }

    function _onBurn(uint256 lockerId_, address staker) internal {
        require(!_isFrozen(staker), "Staker is frozen");
        if (_laggingSlashedPercentage(lockerId_, staker) != 0) {
            LockerSlashes storage slashes = _slashers.data[staker].totalSlashed[lockerId_];
            slashes.previouslySlashed = 0;
            slashes.percentage = 0;
            emit SlashedStakeBurned(lockerId_, staker);
        }
    }

    function _isFrozen(address staker) internal view returns (bool) {
        return _slashers.data[staker].freezeEnd > block.timestamp;
    }

    function _isFrozenBy(address staker, uint256 service) internal view returns (bool) {
        return _slashers.data[staker].serviceData[_getNonce(staker)][service].frozen;
    }

    function _isLockedIn(address staker, uint256 service) internal view override returns (bool) {
        return super._isLockedIn(staker, service) && _slashers.slashers[service].scheduledTime == 0;
    }

    // WHEN NEW PERIOD STARTS we combine the last period with all the previous periods
    // essentially applied on top of the amount when the old percentage is taken into account
    function _combineSlashingPeriods(uint8 oldSlashing, uint8 newSlashing) private pure returns (uint8) {
        return oldSlashing + ((100 - oldSlashing) * newSlashing) / 100;
    }

    function _getNonce(address staker) private view returns (uint216 nonce) {
        nonce = _slashers.data[staker].nonce;
        if (_slashers.data[staker].freezeEnd < block.timestamp) {
            nonce += 1;
        }
    }
}
