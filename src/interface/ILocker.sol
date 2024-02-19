// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Locker
/// @author Polygon Labs
interface ILocker {
    /// @dev emitted whenever the stake of a staker changes
    /// this can one of 3 things:
    /// - deposit into the locker
    /// - initiate withdrawal from the locker
    /// - slashing
    /// @notice this event is extremely important, as Services need to monitor balance changes
    /// i.e. in order to take action when stakers fall below minumum staking requirements.
    /// Services can then decide wether they want to terminate, slash the staker or both.
    /// This has been moved off-chain because:
    /// 1. It would be very costly to ping all services a staker is subscribed to each time a staker's balance changes
    /// 2. A service's logic may be malicious
    event BalanceChanged(address staker, uint256 newBalance);

    /// @dev Called by the Staking Hub when a staker is subscribing to a service that uses the locker.
    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external;

    /// @dev Called by the Staking Hub when a staker has unsubscribed from a service that uses the locker.
    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external;

    /// @dev Called by the Staking Hub when a staker is slashed
    /// @dev burns funds immediately
    /// @dev Uses freezeStart to snapshot balance if not already snapshotted for that freezeStart.
    function onSlash(address staker, uint256 service, uint8 percentage, uint40 freezeStart) external returns (uint256 newBalance);

    /// @return locker id used to identify the locker in the hub
    function id() external view returns (uint256);

    /// @return amount underlying balance of deposited stake
    function balanceOf(address staker) external view returns (uint256 amount);

    /// @return amount underlying balance restaked to a specific service
    function balanceOf(address staker, uint256 service) external view returns (uint256 amount);

    /// @return votingPower representation of voting power of the staker
    function votingPowerOf(address staker) external view returns (uint256 votingPower);

    /// @return votingPower representation of voting power of the staker for a specific service
    function votingPowerOf(address staker, uint256 service) external view returns (uint256 votingPower);

    /// @return totalSupply total supply of underlying asset deposited into locker
    function totalSupply() external view returns (uint256);

    /// @return totalSupply total supply of underlying asset subscribed to a specific service
    function totalSupply(uint256 service) external view returns (uint256);

    /// @return totalVotingPower total voting power of all stakers
    function totalVotingPower() external view returns (uint256);

    /// @return totalVotingPower total voting power of all stakers subscribed to a specific service
    function totalVotingPower(uint256 service) external view returns (uint256);

    /// @return all services subscribed to by this staker that utilise the locker
    function getServices(address staker) external view returns (uint256[] memory);

    function isSubscribed(address staker, uint256 service) external view returns (bool);
}
