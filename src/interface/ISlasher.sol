// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title Slasher
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
interface ISlasher {
    /// @notice Temporarily prevents a Staker from taking action.
    /// @notice This period can be used to prove the Staker should be slashed.
    /// @dev Called by TODO
    /// @dev Calls onFreeze on the Hub.
    function freeze(address staker) external;

    /// @notice Takes a portion of a Staker's funds away.
    /// @notice The Staker must be frozen first.
    /// @dev Called by TODO
    /// @dev Calls onSlash on the Hub.
    function slash(address staker, uint8 percentage) external;
}
