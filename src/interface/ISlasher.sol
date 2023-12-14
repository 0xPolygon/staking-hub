// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Purpose: Service contract can be upgradeable while not introducting risk with slashing.
interface ISlasher {
    /// @notice Slashes a Staker.
    /// @dev Calls onSlash on the Hub.
    /// @dev Permissionless?
    function freeze(uint256 service, address staker) external;

    function slash(uint256 service, address staker, uint8 percentage) external;
}
