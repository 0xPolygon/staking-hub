// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct ServiceStorage {
    mapping(address staker => mapping(uint256 service => uint256 index)) serviceIndices;
    mapping(address staker => uint256[]) services;
}

library ServiceTracker {
    function addService(ServiceStorage storage store, address staker, uint256 service) internal {
        require(store.serviceIndices[staker][service] == 0, "Service already exists");
        store.services[staker].push(service);
        uint256 index = store.services[staker].length;
        store.serviceIndices[staker][service] = index;
    }

    function removeService(ServiceStorage storage store, address staker, uint256 service) internal {
        uint256 searchIndex = store.serviceIndices[staker][service];
        require(searchIndex != 0, "Service does not exist");
        uint256 lastIndex = store.services[staker].length;
        if (searchIndex != lastIndex) {
            uint256 lastService = store.services[staker][lastIndex - 1];
            store.services[staker][searchIndex - 1] = lastService;
            store.serviceIndices[staker][lastService] = searchIndex;
        }
        store.services[staker].pop();
        store.serviceIndices[staker][service] = 0;
    }

    function getServices(ServiceStorage storage store, address staker) internal view returns (uint256[] memory) {
        return store.services[staker];
    }

    function isSubscribed(ServiceStorage storage store, address staker, uint256 service) internal view returns (bool) {
        return store.serviceIndices[staker][service] != 0;
    }
}
