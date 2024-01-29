// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IStrategy} from "./interface/IStrategy.sol";

/// @title BaseStrategy
/// @author Polygon Labs
/// @notice A Strategy holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.
abstract contract BaseStrategy is IStrategy {
    address public stakingHub;

    mapping(uint256 => uint256) totalSupplies;

    // events
    event Staked(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage);
    event Unstaked(address staker, uint256 service);
    event Slashed(address staker, uint8 percentage);

    constructor(address _stakingHub) {
        stakingHub = _stakingHub;
    }

    // FUNCTIONS TO IMPLEMENT
    function balanceOf(address staker) public view virtual returns (uint256);
    function _onSlash(address user, uint256 service, uint256 amount) internal virtual;
    function _onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage) internal virtual;
    function _onUnstake(address staker, uint256 service, uint256 amount) internal virtual;

    /// @dev Triggered by the Hub when a staker gets slashed on penalized
    function onSlash(address user, uint256 service, uint256 amount) external {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        totalSupplies[service] -= amount;

        _onSlash(user, service, amount);
    }

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.
    /// @dev Triggered before `onRestake` on the Service.
    function onRestake(
        address staker,
        uint256 service,
        uint256 lockingInUntil, // review not required here, keep it?
        uint256 amount,
        uint8 maximumSlashingPercentage
    ) external override {
        totalSupplies[service] += amount;

        _onRestake(staker, service, lockingInUntil, amount, maximumSlashingPercentage);
    }

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.
    /// @dev Triggered after `onUnstake` on the Service.
    function onUnstake(address staker, uint256 service, uint256 amount) external override {
        totalSupplies[service] -= amount;

        _onUnstake(staker, service, amount);
    }
}
