// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct ServiceData {
    uint256[] services;
    uint256[] lockIns;
}

struct ServiceStorage {
    mapping(address staker => mapping(uint256 service => uint256 index)) serviceIndices;
    mapping(address staker => ServiceData) services;
}

library ServiceTracker {
    function addService(ServiceStorage storage store, address staker, uint256 service, uint256 lockInUntil) internal {
        require(store.serviceIndices[staker][service] == 0, "Service already exists");
        store.services[staker].services.push(service);
        store.services[staker].lockIns.push(lockInUntil);
        uint256 index = store.services[staker].services.length;
        store.serviceIndices[staker][service] = index;
    }

    // TODO This function seems off.
    function removeService(ServiceStorage storage store, address staker, uint256 service) internal {
        uint256 searchIndex = store.serviceIndices[staker][service];
        require(searchIndex != 0, "Service does not exist");
        uint256 lastIndex = store.services[staker].services.length;
        if (searchIndex != lastIndex) {
            uint256 lastService = store.services[staker].services[lastIndex - 1];
            store.services[staker].services[searchIndex - 1] = lastService;
            store.serviceIndices[staker][lastService] = searchIndex;
        }
        store.services[staker].services.pop();
        store.services[staker].lockIns.pop();
        store.serviceIndices[staker][service] = 0;
    }

    function getServices(ServiceStorage storage store, address staker) internal view returns (uint256[] memory) {
        return store.services[staker].services;
    }

    function getServicesAndLockIns(ServiceStorage storage store, address staker) internal view returns (uint256[] memory services, uint256[] memory lockIns) {
        return (store.services[staker].services, store.services[staker].lockIns);
    }

    function isSubscribed(ServiceStorage storage store, address staker, uint256 service) internal view returns (bool) {
        return store.serviceIndices[staker][service] != 0;
    }
}
