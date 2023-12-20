// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @notice Purpose: Service contract can be upgradeable while not introducting risk with slashing.
interface ISlasher {
    /// @notice Freezes a Staker.
    /// @dev Calls onFreeze on the Hub.
    function freeze(address staker) external;

    /// @notice Slashes a Staker.
    /// @dev Calls onSlash on the Hub.
    function slash(address staker, uint8 percentage) external;
}
