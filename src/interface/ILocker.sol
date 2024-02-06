// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Locker
/// @author Polygon Labs
/// @notice A Locker holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Locker before subscribing to a Services that uses the Locker.
interface ILocker {
    // ========== TRIGGERS ==========

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Locker.
    /// @dev Triggered before `onRestake` on the Service.
    function onRestake(address staker, uint256 service, uint256 amountOrId, uint8 maxSlashingPercentage) external returns (uint256 newStake);

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Locker.
    /// @dev Triggered after `onUnstake` on the Service.
    function onUnstake(address staker, uint256 service, uint256 amountOrId) external returns (uint256 remainingStake);

    /// @notice Takes a portion of a Staker's funds away.
    /// @dev Called by the Hub when a Staker has been slashed by a Slasher of a Service that uses the Locker.
    function onSlash(address staker, uint256 service, uint256 amountOrId) external;

    // ========== QUERIES ==========

    /// @return balanceInLocker The amount of funds the Staker has in the Locker.
    function balanceOf(address staker) external view returns (uint256 balanceInLocker);

    /// @return balanceInService The amount of funds from the Locker the Staker has staked in a Service.
    function balanceOfIn(address staker, uint256 service) external view returns (uint256 balanceInService);
}
