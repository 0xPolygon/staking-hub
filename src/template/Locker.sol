// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILocker} from "../interface/ILocker.sol";

/// @title Locker
/// @author Polygon Labs
/// @notice A Locker holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Locker before subscribing to a Services that uses the Locker.
abstract contract Locker is ILocker {
    address public stakingHub;

    mapping(uint256 => uint256) public totalSupplies;

    // events
    event Restaked(address staker, uint256 service, uint256 lockingInUntil, uint256 amountOrId, uint8 maximumSlashingPercentage);
    event Unstaked(address staker, uint256 service, uint256 amountOrId);
    event Slashed(address staker, uint256 amountOrId);

    constructor(address _stakingHub) {
        stakingHub = _stakingHub;
    }

    // FUNCTIONS TO IMPLEMENT
    function balanceOf(address staker) public view virtual returns (uint256);
    function _onSlash(address user, uint256 service, uint256 amountOrId) internal virtual;
    function _onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 amountOrId, uint8 maximumSlashingPercentage) internal virtual;
    function _onUnstake(address staker, uint256 service, uint256 amountOrId) internal virtual;

    /// @dev Triggered by the Hub when a staker gets slashed on penalized
    function onSlash(address user, uint256 service, uint256 amountOrId) external {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        totalSupplies[service] -= amountOrId;

        _onSlash(user, service, amountOrId);
        emit Slashed(user, amountOrId);
    }

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Locker.
    /// @dev Triggered before `onRestake` on the Service.
    function onRestake(
        address staker,
        uint256 service,
        uint256 lockingInUntil, // review not required here, keep it?
        uint256 amountOrId,
        uint8 maximumSlashingPercentage
    ) external override {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        totalSupplies[service] += amountOrId;

        _onRestake(staker, service, lockingInUntil, amountOrId, maximumSlashingPercentage);
        emit Restaked(staker, service, lockingInUntil, amountOrId, maximumSlashingPercentage);
    }

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Locker.
    /// @dev Triggered after `onUnstake` on the Service.
    function onUnstake(address staker, uint256 service, uint256 amountOrId) external override {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        totalSupplies[service] -= amountOrId;

        _onUnstake(staker, service, amountOrId);
        emit Unstaked(staker, service, amountOrId);
    }
}
