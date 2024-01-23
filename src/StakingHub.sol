// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IService} from "src/IService.sol";
import {IStrategy} from "src/IStrategy.sol";
import {Subscriptions, SubscriptionsStd} from "src/lib/SubscriptionsStd.sol";

/// @title Polygon Hub
/// @author Polygon Labs
/// @notice The Hub is a permissionless place where Stakers and Services gather.
/// @notice The goal is to create new income streams for Stakers. Meanwhile, Services can acquire Stakers.
/// @notice Stakers can subscribe to Services (i.e., restake) via Strategies.
contract Hub {
    // ========== DATA TYPES ==========

    using SubscriptionsStd for Subscriptions;

    // Review: Do we want to allow the Service to update strategies?
    struct ServiceData {
        IService service;
        uint256[] strategies;
        mapping(uint256 strategyId => uint256 percentage) maximumSlashingPercentages;
        address slasher;
    }

    struct SlasherUpdate {
        address newSlasher;
        uint256 scheduledTime;
    }

    struct StrategyData {
        IStrategy strategy;
        uint256[] services;
    }

    struct SlashingInput {
        uint256 strategyId;
        uint256 percentage;
    }

    // ========== PARAMETERS ==========

    // Note: Placeholders.
    uint256 private constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 private constant STAKER_FREEZE_PERIOD = 7 days;

    // ========== INTERNAL RECORDS ==========

    // Review: Should we use IDs or just addresses? The latter is more gas efficient. Otherwise, we may want to record addresses instead of IDs for stuff like what Strategies a Services uses, so we don't have to look them up in for loops in functions such as subscribe.
    uint256 private _strategyCounter;
    uint256 private _serviceCounter;

    // ========== SERVICE & STRATEGY DATA ==========

    mapping(address strategy => uint256 strategyId) public strategies;
    mapping(address service => uint256 serviceId) public services;

    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;
    mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdate;

    mapping(uint256 strategyId => StrategyData strategyData) public strategyData;

    // ========== STAKER DATA ==========

    mapping(address staker => Subscriptions subscriptions) public subscriptions;

    // ========== EVENTS ==========

    event StrategyRegistered(address indexed strategy, uint256 indexed strategyId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address newSlasher);

    // ========== ACTIONS ==========

    /// @notice Adds a new Strategy to the Hub.
    /// @dev Called by the Strategy.
    function registerStrategy() external returns (uint256 id) {
        require(strategies[msg.sender] == 0, "Strategy already registered");

        // Add the Strategy.
        id = ++_strategyCounter;
        strategies[msg.sender] = id;
        strategyData[id].strategy = IStrategy(msg.sender);

        emit StrategyRegistered(msg.sender, id);
    }

    /// @notice Adds a new Service to the Hub.
    /// @dev Called by the Service.
    function registerService(uint256[] calldata strategies_, SlashingInput[] calldata maximumSlashingPercentages, address slasher)
        external
        returns (uint256 id)
    {
        require(strategies[msg.sender] == 0, "Service already registered");
        for (uint256 i = 0; i < strategies_.length; ++i) {
            uint256 strategyId = strategies_[i];
            require(strategyId <= _strategyCounter, "Strategy does not exist");
            for (uint256 j = i + 1; j < strategies_.length; ++j) {
                require(strategyId != strategies_[j], "Duplicate strategy");
            }
        }

        // Add the Service.
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id].service = IService(msg.sender);
        serviceData[id].strategies = strategies_;
        for (uint256 i; i < maximumSlashingPercentages.length; ++i) {
            SlashingInput calldata maximumSlashingPercentage = maximumSlashingPercentages[i];
            serviceData[id].maximumSlashingPercentages[maximumSlashingPercentage.strategyId] = maximumSlashingPercentage.percentage;
        }
        serviceData[id].slasher = slasher;

        // Link the Service to the Strategies that it uses.
        for (uint256 i; i < strategies_.length; ++i) {
            strategyData[strategies_[i]].services.push(id);
        }

        emit ServiceRegistered(msg.sender, id);
    }

    // Review: Does extending a subscription make sense with the active/locked-in separation? Extending a subscription would mean extending the time the Staker is locked-in with the Service because all subscriptions remain active until the Staker unsubscribes.
    // Answer: Yes, extend the lock in period.
    // Note: Subscription auto-renewals (where a Service can call subscribe on behalf of a Staker) aren't supported.
    /// @notice Subscribes a Staker to a Service.
    /// @notice Extends the lock-in period if the Staker is already subscribed to the Service.
    /// @notice By restaking, the Staker subscribes to the Service, subject to that Service's contract logic.
    /// @dev Called by the Staker.
    /// @dev Calls `onSubscribe` on all Strategies the Service uses.
    /// @dev Calls `onSubscribe` on the Service.
    function restake(uint256 serviceId, uint256 lockInUntil) external {
        require(serviceId <= _serviceCounter, "Invalid Service");
        require(lockInUntil == 0 || lockInUntil > block.timestamp, "Invalid lock-in");
        require(
            !subscriptions[msg.sender].isActive(serviceId) || lockInUntil > subscriptions[msg.sender].getUnlock(serviceId), "Existing subscription not extended"
        ); // review

        // Activate a new subscription or extend the lock-in period of the existing one.
        subscriptions[msg.sender].track(serviceId, lockInUntil); // review

        // Alert the Strategies that the Staker has subscribed.
        // Reverting not allowed.
        // Note: We assume the Service trusts the Strategies to not revert by causing the call to run out of gas.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            uint256 maximumSlashingPercentage = serviceData[serviceId].maximumSlashingPercentages[strategyId];
            try strategyData[strategyId].strategy.onRestake(msg.sender, serviceId, lockInUntil, maximumSlashingPercentage) {} catch {}
        }

        // Confirm the subscription with the Service.
        // The Service can revert.
        serviceData[serviceId].service.onSubscribe(msg.sender, lockInUntil);
    }

    // Review: Should a Service be able to unusubscribe a Staker?
    // Answer: Yes. at any moment
    // What about auto-renewals? In that case the Staker needs to initiate unsubscription *before* the lock-in expires. See the review for `onFreeze`.
    // Answer: no, see above
    // TODO: Announce if after lockin (return true/false) [or always init OR perhaps force]. Keep freezing in mind after annoucing. Also the case of slasher update - this needs to be quicker
    /// @notice Unsubscribes a Staker from a Service.
    /// @notice Let's the Staker unsubscribe immediately if the Service has scheduled a Slasher update.
    /// @notice By unstaking completely, the Staker unsubscribes from the Service, subject to that Service's contract logic.
    /// @dev Called by the Staker.
    /// @dev Calls `onSubscribe` on the Service.
    /// @dev Calls `onSubscribe` on all Strategies the Service uses.
    function unstake(uint256 serviceId) external {
        require(serviceId <= _serviceCounter, "Invalid service");
        require(subscriptions[msg.sender].isActive(serviceId), "Not subscribed");
        require(!subscriptions[msg.sender].isFrozen(serviceId), "Cannot unsubscribe while frozen");

        // Let the Staker unsubscribe if the Service has scheduled a Slasher update.
        // Reverting not allowed.
        // Note: We assume the Staker trusts the Service to not revert by causing the call to run out of gas.
        if (slasherUpdate[serviceId].newSlasher != address(0)) {
            try serviceData[serviceId].service.onUnsubscribe(msg.sender) {} catch {}
        } else {
            // Confirm the unsubscription with the Service if the Staker is still locked-in.
            // The Service can revert.
            if (subscriptions[msg.sender].isLockedIn(serviceId)) {
                serviceData[serviceId].service.onUnsubscribe(msg.sender);
            } else {
                // Let the Staker unsubscribe if the Staker is no longer locked-in.
                // Alert the Service that the Staker has unsubscribed.
                // Reverting not allowed.
                // Note: We assume the Staker trusts the Service to not revert by causing the call to run out of gas.
                try serviceData[serviceId].service.onUnsubscribe(msg.sender) {} catch {}
            }
        }

        // Alert the Strategies that the Staker has unsubscribed.
        // Reverting not allowed.
        // Note: We assume the Staker trust the Strategies to not revert by causing the call to run out of gas.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onUnstake(msg.sender, serviceId) {} catch {}
        }

        // Deactivate the subscription.
        subscriptions[msg.sender].stopTracking(serviceId);
    }

    /// @notice Schedule a Slasher update for a Service.
    /// @dev Called by the Service.
    function initiateSlasherUpdate(address newSlasher) external returns (uint256 scheduledTime) {
        uint256 serviceId = services[msg.sender];
        SlasherUpdate storage update = slasherUpdate[serviceId];

        require(update.scheduledTime == 0, "Slasher update already initiated");

        // Schedule the Slasher update.
        scheduledTime = block.timestamp + SLASHER_UPDATE_TIMELOCK;
        update.newSlasher = newSlasher;
        update.scheduledTime = scheduledTime;

        emit SlasherUpdateInitiated(serviceId, newSlasher);
    }

    /// @notice Apply a scheduled Slasher update for a Service.
    /// @dev Called by anyone.
    function finalizeSlasherUpdate() external {
        uint256 serviceId = services[msg.sender];
        SlasherUpdate storage update = slasherUpdate[serviceId];

        require(block.timestamp >= update.scheduledTime, "Slasher cannot be updated yet");

        // Apply the scheduled Slasher update.
        serviceData[serviceId].slasher = update.newSlasher;

        delete slasherUpdate[services[msg.sender]];
    }

    // ========== TRIGGERS ==========

    // Review: We need to think about freezing edge-cases. For example, if a subscriptions auto-renews, but the Staker is frozen at a time when it's too late for them to unsubscribe. See the review for `unsubscribe`.
    // Answer: this edge case is not possible because there are no auto-renewals.
    /// @notice Temporarily prevents a Staker from unsubscribing from a Service.
    /// @notice This period can be used to prove the Staker should be slashed.
    /// @dev Called by a Slasher of the Service.
    function onFreeze(uint256 serviceId, address staker) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can freeze");

        // Note: We assume the Staker trusts the Service not to freeze them repeatedly.
        subscriptions[msg.sender].freeze(serviceId, block.timestamp + STAKER_FREEZE_PERIOD);

        // Alert the Services that the Staker has been frozen.
        // Reverting not allowed.
        // TODO: We assume the Slasher trusts the Staker to not revert by causing the call to run out of gas. (!!!)
        uint256 currentServiceId = subscriptions[msg.sender].head;
        while (currentServiceId != 0) {
            try serviceData[currentServiceId].service.onFreeze(staker) {} catch {}
            currentServiceId = subscriptions[msg.sender].iterate(currentServiceId);
        }
    }

    /// @notice Takes a portion of a Staker's funds away.
    /// @notice The Staker must be frozen first.
    /// @dev Called by a Slasher of a Service.
    /// @dev Calls onSlash on all Strategies the Services uses.
    function onSlash(uint256 serviceId, address staker, SlashingInput[] calldata percentages) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can slash");
        require(subscriptions[staker].isFrozen(serviceId), "Staker not frozen");
        // TODO Do not allow duplicates. Do not allow Strategies not used.
        for (uint256 i; i < percentages.length; ++i) {
            SlashingInput calldata percentage = percentages[i];
            require(
                percentage.percentage <= serviceData[serviceId].maximumSlashingPercentages[percentage.strategyId], "Slashing percentage exceeds the maximum"
            );
        }

        // Alert all Strategies used by the Service that the Staker has been slashed.
        // Reverting not allowed.
        // TODO: We assume the Slasher trusts the Staker to not revert by causing the call to run out of gas. (!!!)
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
            try strategyData[strategyId].strategy.onSlash(staker, percentage) {} catch {}
        }

        // Unfreeze the Staker.
        subscriptions[staker].unfreeze(serviceId);
    }

    // ========== QUERIES ==========

    function hasActiveSubscriptions(address staker) external view returns (bool) {
        return subscriptions[staker].head != 0;
    }

    // Review: What endpoints are needed? For example: isSubscribed(staker) returns (isActive, isLockedIn)
}
