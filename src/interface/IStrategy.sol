// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title Strategy
/// @author Polygon Labs
/// @notice A Strategy holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.
interface IStrategy {
    // ========== ACTIONS ==========

    // TODO: What to do with these?

    /// @notice Adds funds to be available to a Staker for restaking.
    /// @dev Called by the Staker.
    function deposit() external virtual;

    /// @notice Retrieves [all/a partion of] Staker's funds from the Strategy.
    /// @notice The Staker must be unsubscribed from all Services first. // TODO: outdated
    /// @dev Called by the Staker.
    function withdraw() external virtual;

    // ========== TRIGGERS ==========

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.
    /// @dev Triggered before `onRestake` on the Service.
    function onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 maximumSlashingPercentage) external;

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.
    /// @dev Triggered after `onUnstake` on the Service.
    function onUnstake(address staker, uint256 service) external;

    /// @notice Takes a portion of a Staker's funds away.
    /// @dev Called by the Hub when a Staker has been slashed by a Slasher of a Service that uses the Strategy.
    function onSlash(address staker, uint256 percentage) external;

    // ========== QUERIES ==========

    /// @return The amount of funds the Staker has in the Strategy.
    function balanceOf(address staker) external view returns (uint256);
}
