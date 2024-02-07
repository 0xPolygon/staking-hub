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
}
