// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";

import {ILocker} from "../interface/ILocker.sol";

import {StakingLayerStorage} from "./StakingLayerStorage.sol";
import {PackedUints} from "../lib/PackedUints.sol";

struct UnstakingNotice {
    uint256[] amountsOrIds;
    uint256 scheduledTime;
}

struct SlashingInput {
    uint256 lockerId;
    uint8 percentage;
}

struct ServiceData {
    IService service;
    uint256[] lockers;
    uint256 slashingPercentages;
    uint256 unstakingNoticePeriod;
    mapping(address staker => UnstakingNotice unstakingNotice) unstakingNotice; // TODO Convert to queue per service (context: the current system allows the Staker only one unstaking notice at a time per Service)
    address slasher; // Review: Can multiple Services use the same Slasher? If so, we'll need some guardrails.
    uint256 lastSlasherUpdate;
}

contract StakingLayerManager is StakingLayerStorage {
    using PackedUints for uint256;

    uint256 internal _lockerCounter;
    uint256 internal _serviceCounter;

    mapping(address locker => uint256 lockerId) public lockers;
    mapping(address service => uint256 serviceId) public services;
    mapping(uint256 lockerId => ILocker locker) public lockerAddresses;
    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;

    /// @notice Adds a new Locker to the Hub.
    /// @dev Called by the Locker.
    function registerLocker() external returns (uint256 id) {
        require(lockers[msg.sender] == 0, "Locker already registered");

        // Add the Locker.
        id = ++_lockerCounter;
        lockers[msg.sender] = id;
        lockerAddresses[id] = ILocker(msg.sender);

        emit LockerRegistered(msg.sender, id);
    }

    /// @notice Adds a new Service to the Hub.
    /// @param lockers_.percentage Use `0` or `100` for ERC-721 tokens.
    /// @dev Called by the Service.
    function registerService(SlashingInput[] calldata lockers_, uint256 unstakingNoticePeriod, address slasher) external returns (uint256 id) {
        require(services[msg.sender] == 0, "Service already registered");
        require(lockers_.length < 33, "Limit Lockers to 32");
        _validateLockerInputs(lockers_);

        // Add the Service.
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id].service = IService(msg.sender);
        uint256 slashingPercentages;
        for (uint256 i; i < lockers_.length; ++i) {
            serviceData[id].lockers.push(lockers_[i].lockerId);
            slashingPercentages = slashingPercentages.set(lockers_[i].percentage, i);
        }
        serviceData[id].slashingPercentages = slashingPercentages;
        serviceData[id].unstakingNoticePeriod = unstakingNoticePeriod;
        serviceData[id].slasher = slasher;

        emit ServiceRegistered(msg.sender, id);
    }

    /// @dev Reverts if a Locker does not exist, or a duplicate is found.
    /// @dev locker ids must be sorted in ascending order for duplicate check
    function _validateLockerInputs(SlashingInput[] calldata lockers_) internal view {
        uint256 lastId;
        uint256 len = lockers_.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 lockerId = lockers_[i].lockerId;
            require(lockerId > lastId, "Duplicate Locker or Unsorted List");
            require(lockers_[i].percentage <= 100, "Invalid slashing percentage");
        }
        require(lastId <= _lockerCounter, "Invalid Locker");
    }
}
