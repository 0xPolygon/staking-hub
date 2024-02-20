// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {LockerSettings} from "../interface/IStakingHub.sol";
import {StakerManager} from "./StakerManager.sol";
import {PackedUints} from "../lib/PackedUints.sol";
import {IService} from "../interface/IService.sol";
import {ILocker} from "../interface/ILocker.sol";

abstract contract ServiceManager is StakerManager {
    using PackedUints for uint256;

    struct Service {
        address service;
        uint256[] lockers;
        uint256 slashingPercentages;
        uint40 unsubNotice;
    }

    struct ServiceStorage {
        uint256 counter;
        mapping(address => uint256) ids;
        mapping(uint256 => Service) data;
    }

    ServiceStorage internal _services;

    function _setService(address service, uint256[] memory lockers, uint256 slashingPercentages, uint40 unsubNotice) internal returns (uint256 id) {
        require(service.code.length != 0, "Service contract not found");
        require(_services.ids[service] == 0, "Service already registered");
        require(unsubNotice > 0, "Invalid unsubscription notice");
        id = ++_services.counter;
        _services.ids[service] = id;
        _services.data[id] = Service(service, lockers, slashingPercentages, unsubNotice);
        emit ServiceRegistered(service, id);
    }

    function _formatLockers(LockerSettings[] calldata lockers) internal view returns (uint256[] memory formatted, uint256 slashingPercentages) {
        _validateLockers(lockers);
        uint256 len = lockers.length;
        formatted = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            formatted[i] = lockers[i].lockerId;
            slashingPercentages.set(lockers[i].maxSlashPercentage, i);
        }
    }

    function _validateLockers(LockerSettings[] calldata lockers) private view {
        uint256 len = lockers.length;
        if (len == 0 || len > 32) revert("Invalid number of lockers");
        uint256 lastId;
        for (uint256 i = 0; i < len; ++i) {
            uint256 lockerId_ = lockers[i].lockerId;
            require(lockerId_ > lastId, "Duplicate Locker or unsorted list");
            require(lockers[i].maxSlashPercentage < 101, "Invalid max slash percentage");
        }
        require(lastId <= _lockerStorage.counter, "Invalid locker");
    }

    function _serviceId(address service) internal view returns (uint256 id) {
        id = _services.ids[service];
        require(id != 0, "Service not registered");
    }

    function _service(uint256 id) internal view returns (IService service) {
        service = IService(_services.data[id].service);
        require(address(service) != address(0), "Service not registered");
    }

    function _lockers(uint256 id) internal view returns (uint256[] memory lockers) {
        lockers = _services.data[id].lockers;
    }

    function _slashingPercentages(uint256 id) internal view returns (uint256 slashingPercentages) {
        slashingPercentages = _services.data[id].slashingPercentages;
    }

    function _slashingPercentage(uint256 id, uint256 index) internal view returns (uint8 percentage) {
        percentage = _services.data[id].slashingPercentages.get(index);
    }

    function _unsubNotice(uint256 id) internal view override returns (uint40 notice) {
        notice = _services.data[id].unsubNotice;
    }

    function _isSubscribed(address staker, uint256 id) internal view returns (bool) {
        return _stakers.subscriptions[staker][id].subscribed;
    }
}
