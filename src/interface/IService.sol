// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// TODO Is it outdated?
/// @title Service
/// @author Polygon Labs
/// @notice A Service represents a network.
/// @notice Stakers can subscribe to the Service by restaking.
interface IService {
    // ========== TRIGGERS ==========

    /// @notice Lets a Staker restake in the Service.
    /// @notice Performs all neccessary checks on the Staker (e.g., voting power, whitelist, BLS-key, etc.).
    /// @dev Called by the Hub when a Staker subscribes to the Service.
    /// @dev The Service can revert.
    /// @param staker The address of the Staker
    function onSubscribe(address staker) external;

    /// @notice Lets a Staker unstake from the Service.
    /// @notice Performs all neccessary checks on the Staker.
    /// @notice A Service that requires unstaking notice may still choose allow the Staker to finalize the unstaking immediately.
    /// @dev Called by the Hub when a Staker unsubscribes from the Service.
    /// @dev The Service can revert when the subscription hasn't expired.
    /// @param staker The address of the Staker
    function onCancelSubscription(address staker) external returns (bool finalizeImmediately);

    /// @dev Triggered by hub.
    /// @dev Reverting not allowed if staker is not locked-in.
    /// @param staker The address of the Staker
    function onUnsubscribe(address staker) external;
}
