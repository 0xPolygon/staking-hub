// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// TODO Is it outdated?
/// @title Service
/// @author Polygon Labs
/// @notice A Service represents a network.
/// @notice Stakers can subscribe to the Service by restaking.
interface IService {
    // ========== TRIGGERS ==========

    /// @notice Lets a Staker unstake from the Service.
    /// @notice Performs all neccessary checks on the Staker.
    /// @notice A Service that requires unstaking notice may still choose allow the Staker to finalize the unstaking immediately.
    /// @dev Called by the Hub when a Staker unsubscribes from the Service.
    /// @dev The Service can revert when the subscription hasn't expired.
    function onCancelSubscription(address staker) external returns (bool finalizeImmediately);
    function onUnsubscribe(address staker) external;

    /// @notice Functionality not defined.
    /// @dev Called by the Hub when a Staker has been frozen by a Slasher of the Service.
    function onFreeze(address staker) external;
}
