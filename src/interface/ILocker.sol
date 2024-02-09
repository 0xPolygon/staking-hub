// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Locker
/// @author Polygon Labs
/// @notice A locker holds and manages stakers' funds.
/// @notice A staker deposits funds into the locker before subscribing to services that uses that locker.
interface ILocker {
    /// @dev Triggered by the Staking Layer when a staker is subscribing to a service that uses the locker.
    function onSubscribe(address staker, uint256 service, uint8 maxSlashingPercentage) external;

    /// @dev Called by the Staking Layer when a staker has unsubscribed from a service that uses the locker.
    function onUnsubscribe(address staker, uint256 service) external;

    /// @return amount underlying balance of deposited stake
    function balanceOf(address staker) external view returns (uint256 amount);

    /// @return votingPower representation of voting power of the staker
    function votingPowerOf(address staker) external view returns (uint256 votingPower);

    /// @return totalSupply total supply of underlying asset deposited into locker
    function totalSupply() external view returns (uint256);

    /// @return totalVotingPower total voting power of all stakers
    function totalVotingPower() external view returns (uint256);
}
