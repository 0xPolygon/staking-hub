// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILocker} from "../interface/ILocker.sol";
import {StakingLayer} from "../StakingLayer/StakingLayer.sol";

/// @title Locker
/// @author Polygon Labs
/// @notice A Locker holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Locker before subscribing to a Services that uses the Locker.
abstract contract Locker is ILocker {
    StakingLayer public stakingHub;

    mapping(uint256 => uint256) public totalSupplies;
    mapping(address staker => mapping(uint256 service => uint256 balance)) public balancesIn;

    mapping(address => uint256) slashableAmount;
    mapping(uint256 service => uint8) slashPercentages;

    // events
    event Restaked(address staker, uint256 service, uint256 amountOrId, uint8 maximumSlashingPercentage);
    event Unstaked(address staker, uint256 service, uint256 amountOrId);
    event Slashed(address staker, uint256 service, uint256 amountOrId);

    constructor(address _stakingHub) {
        stakingHub = _stakingHub;

        // register
        stakingHub.registerLocker();
    }

    // FUNCTIONS TO IMPLEMENT
    function balanceOf(address staker) public view virtual returns (uint256);
    function _onSlash(address user, uint256 service, uint256 amountOrId) internal virtual;
    function _onRestake(address staker, uint256 service, uint256 amountOrId, uint8 maximumSlashingPercentage) internal virtual;
    function _onUnstake(address staker, uint256 service, uint256 amountOrId) internal virtual;

    /// @dev Triggered by the Hub when a staker gets slashed on penalized
    function onSlash(address user, uint256 service, uint256 amountOrId) external {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        totalSupplies[service] -= amountOrId;

        _onSlash(user, service, amountOrId);
        emit Slashed(user, service, amountOrId);
    }

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Locker.
    /// @dev Triggered before `onRestake` on the Service.
    function onRestake(
        address staker,
        uint256 service,
        uint256 amountOrId,
        uint8 maxSlashingPercentage
    ) external override returns (uint256 newStake) {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");
        enforceRestakingLimit(staker, service, amountOrId, maxSlashingPercentage);

        totalSupplies[service] += amountOrId;

        balancesIn[staker][service] += amountOrId;

        _onRestake(staker, service, amountOrId, maxSlashingPercentage);
        emit Restaked(staker, service, amountOrId, maxSlashingPercentage);

        return balancesIn[staker][service];
    }

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Locker.
    /// @dev Triggered after `onUnstake` on the Service.
<<<<<<< HEAD
    function onUnstake(address staker, uint256 service, uint256 amountOrId) external {
=======
    function onUnstake(address staker, uint256 service, uint256 amountOrId) external override returns (uint256 remainingStake) {
>>>>>>> dev
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        balancesIn[staker][service] -= amountOrId;

        totalSupplies[service] -= amountOrId;

        uint256 slashChange = (amountOrId * slashPercentages[service]) / 100;
        slashableAmount[staker] -= slashChange;

        _onUnstake(staker, service, amountOrId);
        emit Unstaked(staker, service, amountOrId);

        return balancesIn[staker][service];
    }

    function balanceOfIn(address staker, uint256 service) public view returns (uint256 balanceInService) {
        // TODO substract slashed amount (found in StakingLayer)
        return balancesIn[staker][service];
    }

    function enforceRestakingLimit(address staker, uint256 service, uint256 amount, uint8 maximumSlashingPercentage) private {
        // remember slash % for new services
        // review we could either make this a call to StakingLayer or also send it in onUnstake, to get rid of this if clause
        if(slashPercentages[service] == 0) {
            slashPercentages[service] = maximumSlashingPercentage;
        }

        slashableAmount[staker] += (amount * maximumSlashingPercentage) / 100;

        require(slashableAmount[staker] <= balanceOf(staker), "ERC20PartialWithdrawalsStrategy: Slashable amount too high.");
    }

    function totalSupply() public view virtual returns (uint256) {}
}
