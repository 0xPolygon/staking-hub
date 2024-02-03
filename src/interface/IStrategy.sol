// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title Strategy
/// @author Polygon Labs
/// @notice A Strategy holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.
interface IStrategy {
    // ========== TRIGGERS ==========

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.
    /// @dev Triggered before `onRestake` on the Service.
    function onRestake(address staker, uint256 service, uint256 amountOrId, uint256 committingUntil, uint8 maximumSlashingPercentage) external;

    // TODO: Rename.
    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.
    /// @dev Triggered after `onUnstake` on the Service.
    function onUnstake(address staker, uint256 service, uint256 amountOrId) external;

    /// @notice Takes a portion of a Staker's funds away.
    /// @dev Called by the Hub when a Staker has been slashed by a Slasher of a Service that uses the Strategy.
    function onSlash(address staker, uint256 service, uint256 amountOrId) external;

    // ========== QUERIES ==========

    /// @return balanceInStrategy The amount of funds the Staker has in the Strategy.
    function balanceOf(address staker) external view returns (uint256 balanceInStrategy);

    /// @return balanceInService The amount of funds from the Strategy the Staker has staked in a Service.
    function balanceIn(address staker, uint256 service) external view returns (uint256 balanceInService);
}
