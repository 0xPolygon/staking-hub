// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title Slasher Example
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
interface ISlasherExample {
    /// @notice Temporarily prevents a Staker from taking action.
    /// @notice This period can be used to prove the Staker should be slashed.
    /// @dev Called by [up to the Slasher to decide].
    /// @dev Calls onFreeze on the Hub.
    function freeze(address staker, bytes calldata proof) external;

    /// @notice Takes a portion of a Staker's funds away.
    /// @notice The Staker must be frozen first.
    /// @dev Called by [up to the Slasher to decide].
    /// @dev Calls onSlash on the Hub.
    function slash(address staker, uint256 percentage) external;

    // TODO: for slashing (challanging etc) provide that here in the example (from notion - a self-regulating mechanism that the staker trusts)
}
