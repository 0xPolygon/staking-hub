// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {StakingManager} from "./StakingManager.sol";

struct SlasherUpdate {
    address newSlasher;
    uint256 scheduledTime;
}

contract SlashingManager is StakingManager {
    mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdates;

    // NOTE: Updated code through this line. Some logic and docs below may be outdated (except HELPERS)! TODO

    /// @notice Schedule a Slasher update for a Service.
    /// @dev Called by the Service.
    function initiateSlasherUpdate(address newSlasher) external returns (uint256 scheduledTime) {
        uint256 serviceId = services[msg.sender];
        SlasherUpdate storage update = slasherUpdates[serviceId];

        require(update.scheduledTime == 0, "Slasher update already initiated");

        // Schedule the Slasher update.
        scheduledTime = block.timestamp + SLASHER_UPDATE_TIMELOCK;
        update.newSlasher = newSlasher;
        update.scheduledTime = scheduledTime;

        emit SlasherUpdateInitiated(serviceId, newSlasher);
    }

    /// @notice Apply a scheduled Slasher update for a Service.
    /// @dev Called by anyone.
    function finalizeSlasherUpdate(uint256 serviceId) external {
        SlasherUpdate storage update = slasherUpdates[serviceId];

        require(block.timestamp >= update.scheduledTime, "Slasher cannot be updated yet");

        // Apply the scheduled Slasher update.
        serviceData[serviceId].slasher = update.newSlasher;
        serviceData[serviceId].lastSlasherUpdate = block.timestamp;

        delete update;
    }

    // ========== TRIGGERS ==========

    /// @notice Temporarily prevents a staker from performing any action
    /// @notice Can only be called once per service per freeze period
    /// @notice This period can be used to prove the Staker should be slashed.
    /// @dev Called by a Slasher of the Service.
    function onFreeze(uint256 serviceId, address staker) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can freeze");

        // Note: We assume the Staker trusts the Service not to freeze them repeatedly.
        subscriptions[staker].freeze(serviceId, block.timestamp + STAKER_FREEZE_PERIOD);

        // Emit an event for Services that the Staker has been frozen.
        // Note: Never notify any other Services (using the `onFreeze` trigger). Instead, emit an event.
        // TODO: Describe the attack vector. Same for slashing.
        emit StakerFrozen(staker, serviceId);
    }

    /// @notice Takes a portion of a Staker's funds away.
    /// @notice The Staker must be frozen first.
    /// @dev Called by a Slasher of a Service.
    /// @dev Calls onSlash on all Strategies the Services uses.
    // TODO Aggregation (see the new [private/not on GH] Note + make sure to clear all freezes)
    function onSlash(uint256 serviceId, address staker, SlashingInput[] calldata percentages) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can slash");
        require(subscriptions[staker].isFrozen(), "Staker not frozen");
        uint256 maxSlashingPercentages = serviceData[serviceId].slashingPercentages;
        // TODO Do not allow duplicates. Do not allow Strategies not used.
        for (uint256 i; i < percentages.length; ++i) {
            SlashingInput calldata percentage = percentages[i];
            require(percentage.percentage <= maxSlashingPercentages.get(i), "Slashing percentage exceeds maximum");
        }

        // Notify all Strategies used by the Service that the Staker has been slashed.
        // Reverting not allowed.
        // TODO: We assume the Service trusts the Strategies not to revert by causing the call to run out of gas.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            uint256 percentage;
            // Review: Gas-inefficient check.
            for (uint256 j; j < percentages.length; ++j) {
                if (percentages[j].strategyId == strategyId) {
                    percentage = percentages[j].percentage;
                    break;
                }
            }
            // TODO: strategy expects amount, not percentage
            try strategyData[strategyId].strategy.onSlash(staker, serviceId, percentage) {}
            catch (bytes memory data) {
                emit SlashingError(strategyId, msg.sender, staker, data);
            }
        }

        // Unfreeze the Staker.
        subscriptions[staker].unfreeze(serviceId);
    }

    function finalizeSlashing(uint256 strategy, uint256 slashingId) external {
        // TODO
    }

    function onUnfreeze(uint256 serviceId, address staker) external {
        // TODO Add onUnfreeze
    }
}
