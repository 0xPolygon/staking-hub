// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

library PackedUints {
    function set(uint256 store, uint8 value, uint256 index) internal pure returns (uint256) {
        require(index < 32, "PackedUints: index out of range");
        store |= uint256(value) << (index * 8);
        return store;
    }

    function get(uint256 store, uint256 index) internal pure returns (uint8) {
        require(index < 32, "PackedUints: index out of range");
        return uint8(store >> (index * 8));
    }
}
