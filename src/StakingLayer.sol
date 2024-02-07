// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {LockerManager, LockerStorage} from "./lib/LockerManager.sol";
import {ServiceManager, ServiceStorage, SlashingInput} from "./lib/ServiceManager.sol";
import {IStakingLayer} from "./interface/IStakingLayer.sol";

contract StakingLayer is IStakingLayer {
    using LockerManager for LockerStorage;
    using ServiceManager for ServiceStorage;

    LockerStorage internal _lockerStorage;
    ServiceStorage internal _serviceStorage;

    function registerLocker() external returns (uint256 id) {
        id = _lockerStorage.registerLocker();
        emit LockerRegistered(msg.sender, id);
    }

    function registerService(SlashingInput[] calldata lockers, uint40 unstakingNoticePeriod, address slasher) external returns (uint256 id) {
        id = _serviceStorage.registerService(msg.sender, lockers, unstakingNoticePeriod, slasher);
        emit ServiceRegistered(msg.sender, id);
    }

    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime) {
        scheduledTime = _serviceStorage.initiateSlasherUpdate(msg.sender, newSlasher);
        emit SlasherUpdateInitiated(_serviceStorage.getServiceId(msg.sender), newSlasher);
    }

    function finalizeSlasherUpdate() external {
        _serviceStorage.finalizeSlasherUpdate(msg.sender);
        emit SlasherUpdateFinalized(_serviceStorage.getServiceId(msg.sender));
    }

    function restake(uint256 serviceId, uint40 commitUntil) external {
        _serviceStorage.restake(msg.sender, serviceId, commitUntil);
        emit Restaked(msg.sender, serviceId, commitUntil);
        _serviceStorage.getService(serviceId).onRestake(msg.sender);
    }

    function initiateUnstaking(uint256 serviceId) external {
        uint40 commitment = _serviceStorage.initiateUnstaking(msg.sender, serviceId);
        emit UnstakingInitiated(msg.sender, serviceId);
        // if still committed to service call normally, service can chose to revert
        if (commitment > block.timestamp) {
            _serviceStorage.getService(serviceId).onInitializeUnstaking(msg.sender);
        } else {
            try _serviceStorage.getService(serviceId).onInitializeUnstaking(msg.sender) {}
            catch (bytes memory revertData) {
                emit UnstakingError(serviceId, msg.sender, revertData);
            }
        }
    }

    function finalizeUnstake(uint256 serviceId) external {
        uint40 commitment = _serviceStorage.finalizeUnstake(msg.sender, serviceId);
        emit Unstaked(msg.sender, serviceId);
        // if still committed to service call normally, service can chose to revert
        if (commitment > block.timestamp) {
            _serviceStorage.getService(serviceId).onFinalizeUnstaking(msg.sender);
        } else {
            try _serviceStorage.getService(serviceId).onFinalizeUnstaking(msg.sender) {}
            catch (bytes memory revertData) {
                emit UnstakingError(serviceId, msg.sender, revertData);
            }
        }
    }

    function onFreeze(uint256 serviceId, address staker) external {
        _serviceStorage.onFreeze(msg.sender, serviceId, staker);
        emit StakerFrozen(staker, serviceId);
    }

    function onUnfreeze() external {}

    function onSlash() external {}

    function finaliseSlashing() external {}

    // ===============================================================================
    //                              FREEZING AND SLASHING
    // ===============================================================================

    /* This is a simple proof-of-concept.

    Note: This implementation does NOT require unsubscribing the Staker after slashing.
    If we want, we can support BOTH staying AND unsubscribing, and let the Service decide.
    
    A slashing is "settled" immediately.
    However, the funds aren't actually BURNED until `applySlashings` is called by the Locker.
    We call this "applying" the slashings. */

    struct FreezePeriod {
        uint256 start;
        uint256 end;
    }

    mapping(address staker => FreezePeriod freeze) freezeForStaker;

    // Prevents a Staker from taking action.
    function freeze(address staker) external {
        if (!_isFrozen(staker)) _startFreeze(staker);
        else _extendFreeze(staker);
    }

    function _isFrozen(address staker) internal view returns (bool) {
        return freezeForStaker[staker].end < block.timestamp;
    }

    function _startFreeze(address staker) internal {
        freezeForStaker[staker].start = block.timestamp;
        freezeForStaker[staker].end = block.timestamp + ServiceManager.STAKER_FREEZE_PERIOD;
    }

    function _extendFreeze(address staker) internal {
        freezeForStaker[staker].end = block.timestamp + ServiceManager.STAKER_FREEZE_PERIOD;
    }

    // The real-time amount that's slashable FOR STAKER per Service.
    // We use this for the `slashInfoForLocker` mapping to map from Locker => Staker => Service => slashable amount.
    struct SlashAmount {
        uint256 initial; // The `balanceOfIn` at the start of the CURRENT freeze period.
        uint256 current; // The sum of all slashings for the CURRENT freeze period.
        uint256 total; // The sum of all slashings across ALL freeze periods that haven't been "applied" (see `applySlashings`).
        uint256 initialLastUpdated;
    }

    // See `slashInfoForLocker`.
    struct SlashingInfo {
        mapping(uint256 serviceId => SlashAmount amount) amount;
        uint256[] serviceIds;
    }

    // See `getSlashInfo` and `getSlashableStake`.
    mapping(uint256 strategyId => mapping(address staker => SlashingInfo rawInfo)) internal slashInfoForLocker;

    // Keeps the `SlashAmount` struct up-to-date at all times.
    // `initial` will be reset at the start of each new freeze period.
    // `current` will be reset at the start of each new freeze period.
    // `total` will carry over between freeze periods.
    function slash(uint256 serviceId, address staker, uint256[] calldata amounts) external {
        require(_isFrozen(staker), "Staker not frozen");

        uint256[] storage lockers = _serviceStorage.getServiceData(serviceId).lockers;

        for (uint256 i; i < lockers.length; ++i) {
            SlashingInfo storage slashingInfo = slashInfoForLocker[lockers[i]][staker];
            if (slashingInfo.amount[serviceId].initialLastUpdated != freezeForStaker[staker].start) {
                slashingInfo.amount[serviceId].initial = /*balanceOfIn(staker, serviceId) TODO*/ 999;
                slashingInfo.amount[serviceId].initialLastUpdated = freezeForStaker[staker].start;
                slashingInfo.amount[serviceId].current = 0;
                if (slashingInfo.amount[serviceId].total == 0) slashingInfo.serviceIds.push(serviceId);
            }

            // if (new current <= initial * max slash percentage) { TODO
            slashingInfo.amount[serviceId].current += amounts[i];
            slashingInfo.amount[serviceId].total += amounts[i];
            // } else revert("Exceeds maximum");
        }
    }

    // Locker can use this to see how much to slash per Service.
    function getSlashInfo(uint256 lockerId, address staker) external view returns (uint256[] memory serviceIds, uint256[] memory amounts) {
        SlashingInfo storage slashingInfo = slashInfoForLocker[lockerId][staker];
        uint256 length = slashingInfo.serviceIds.length;

        amounts = new uint256[](length);
        for (uint256 i; i < length; ++i) {
            amounts[i] = slashingInfo.amount[slashingInfo.serviceIds[i]].total;
        }

        return (slashingInfo.serviceIds, amounts);
    }

    // Called by the Locker in `balanceOfIn`.
    // See `ILocker.sol`.
    function getSlashableStake(uint256 lockerId, uint256 serviceId, address staker) external view returns (uint256 amountToBeSlashed) {
        amountToBeSlashed = slashInfoForLocker[lockerId][staker].amount[serviceId].total;
    }

    // Called by the Locker to "apply" all unstakings that have pilled up accross different freezing periods.
    // `total` will be reset.
    function applySlashings(address staker) external {
        require(!_isFrozen(staker), "Cannot apply slashings if Staker is frozen");

        SlashingInfo storage slashingInfo = slashInfoForLocker[_lockerStorage.getLockerId(msg.sender)][staker];

        for (uint256 i; i < slashingInfo.serviceIds.length; ++i) {
            delete slashingInfo.amount[slashingInfo.serviceIds[i]].total;
        }
        delete slashingInfo.serviceIds;
    }
}
