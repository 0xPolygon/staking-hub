// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title ISlasher
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
interface ISlasher {
    /// @notice Temporarily prevents a Staker from taking action.
    /// @notice starts grace period in which staker can prove their innocence
    /// @dev Called by a service.
    /// @dev Calls onFreeze on the Hub.
    function freeze(address staker) external;

    /// @notice Unfreezes a Staker.
    /// @notice will be called in case innocence of a staker has been established by a service.
    /// @notice This challenge might happen off-chain.
    /// @dev Called by a service.
    /// @dev Calls onUnfreeze on the Hub.
    function unfreeze(address staker) external;

    /// @notice Takes a portion of a Staker's funds away.
    /// @notice The Staker must be frozen first.
    /// @notice The grace period must have passed.
    /// @dev Called by [up to the Slasher to decide].
    /// @dev Calls onSlash on the Hub.
    function slash(address staker, uint8 percentage) external;

    /// @notice Instantlyakes a portion of a Staker's funds away.
    /// @notice Proof of malice must be submitted and validated by the Slasher
    /// @dev Called by anyone.
    /// @dev Calls onSlash on the Hub.
    function instaSlash(address staker, uint8 percentage, bytes calldata proof) external;
}
