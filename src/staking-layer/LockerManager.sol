// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {IStakingLayer} from "../interface/IStakingLayer.sol";
import {ILocker} from "../interface/ILocker.sol";

abstract contract LockerManager is IStakingLayer {
    struct LockerStorage {
        uint256 counter;
        mapping(address => uint256) ids;
        mapping(uint256 => address) addresses;
    }

    LockerStorage internal _lockerStorage;

    function _setLocker(address newLocker) internal returns (uint256 id) {
        require(newLocker.code.length != 0, "Locker contract not found");
        require(_lockerStorage.ids[newLocker] == 0, "Locker already registered");
        id = ++_lockerStorage.counter;
        _lockerStorage.ids[newLocker] = id;
        _lockerStorage.addresses[id] = newLocker;
        emit LockerRegistered(msg.sender, id);
    }

    function lockerId(address lockerAddr) public view returns (uint256 id) {
        id = _lockerStorage.ids[lockerAddr];
    }

    function locker(uint256 id) public view returns (ILocker locker_) {
        locker_ = ILocker(_lockerStorage.addresses[id]);
        require(address(locker_) != address(0), "Locker not registered");
    }
}
