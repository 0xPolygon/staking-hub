// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title Service
/// @author Polygon Labs
/// @notice A Service represents a network.
/// @notice Stakers can subscribe to the Service (i.e., restake).
abstract contract Service {
    /// @notice Lets a Staker restake with the Service.
    /// @notice Performs all neccessary checks on the Staker (e.g., voting power, whitelist, BLS-key, etc.).
    /// @dev Called by the Hub when a Staker subscribes to the Service.
    /// @dev The Service can revert.
    function onSubscribe(address staker, uint256 stakedUntil) external virtual;

    /// @notice Lets a Staker unstake from the Service.
    /// @notice Performs all neccessary checks on the Staker.
    /// @dev Called by the Hub when a Staker unsubscribes from the Service.
    /// @dev The Service can revert when the subscription hasn't expired.
    function onUnsubscribe(address staker) external virtual;

    /// @notice Functionality not defined.
    /// @dev Called by the Hub when a Staker has been frozen by a Slasher of the Service.
    function onFreeze(address staker) external virtual;
}
