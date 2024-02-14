// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Locker
/// @author Polygon Labs
/// @notice A locker holds and manages stakers' funds.
/// @notice A staker deposits funds into the locker before subscribing to services that uses that locker.
interface ILocker {
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
