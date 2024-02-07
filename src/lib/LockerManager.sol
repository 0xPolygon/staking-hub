// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct LockerStorage {
    uint256 counter;
    mapping(address => uint256) ids;
    mapping(uint256 => address) addresses;
}

library LockerManager {
    function registerLocker(LockerStorage storage self) internal returns (uint256 id) {
        require(self.ids[msg.sender] == 0, "Locker already registered");
        id = ++self.counter;
        self.ids[msg.sender] = id;
        self.addresses[id] = msg.sender;
    }

    function getLockerId(LockerStorage storage self, address locker) internal view returns (uint256 id) {
        id = self.ids[locker];
    }

    function getLockerAddress(LockerStorage storage self, uint256 id) internal view returns (address locker) {
        locker = self.addresses[id];
    }
}
