// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// TODO Is it outdated?
/// @title Locker
/// @author Polygon Labs
/// @notice A Locker holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Locker before subscribing to a Services that uses the Locker.
interface ILocker {
    // ========== TRIGGERS ==========

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Locker.
    /// @dev Triggered before `onRestake` on the Service.
    function onSubscribe(address staker, uint256 service, uint8 maxSlashingPercentage) external;

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Locker.
    /// @dev Triggered after `onUnstake` on the Service.
    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashingPercentage) external;

    // ========== QUERIES ==========

    /// @return amount underlying balance of deposited stake
    function balanceOf(address staker) external view returns (uint256 amount);

    /// @return votingPower representation of voting power of the staker
    function votingPowerOf(address staker) external view returns (uint256 votingPower);

    /// @return totalSupply total supply of underlying asset deposited into locker
    function totalSupply() external view returns (uint256);

    /// @return totalVotingPower total voting power of all stakers
    function totalVotingPower() external view returns (uint256);
}
