// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IService} from "./interface/IService.sol";
import {IStrategy} from "./interface/IStrategy.sol";
import {Subscriptions, SubscriptionsStd} from "./lib/SubscriptionsStd.sol";

/// @title Polygon Hub
/// @author Polygon Labs
/// @notice The Hub is a permissionless place where Stakers and Services gather.
/// @notice The goal is to create new income streams for Stakers. Meanwhile, Services can acquire Stakers.
/// @notice Stakers can subscribe to Services by restaking via Strategies.
contract Hub {
    // ========== DATA TYPES ==========

    using SubscriptionsStd for Subscriptions;

    // Review: Do we want to allow Services to update thier `strategies`?
    struct ServiceData {
        IService service;
        uint256[] strategies;
        mapping(uint256 strategyId => uint8 percentage) maximumSlashingPercentages;
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
        uint8 percentage;
    }

    // ========== PARAMETERS ==========

    // TODO: Those are placeholders.
    uint256 private constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 private constant STAKER_FREEZE_PERIOD = 7 days;

    // ========== INTERNAL RECORDS ==========

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
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);

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

    // Review: See `unstake` review.
    /// @notice Lets a Staker reuse funds they have previously deposited into Strategies used by a Service to increase their stake in that Service.
    /// @notice By restaking, the Staker becomes subscribed to the Service, subject to the terms of the Service.
    /// @notice Restaking may increase the Staker's commitment to the Service if the Staker is already subscribed to the Service. This depends on the `commitUntil` parameter.
    /// @param commitUntil Use `0` to indicate no change in commitment. `commitUntil` will be resolved to a value before further processing.
    /// @dev Called by the Staker.
    /// @dev Triggers `onRestake` on all Strategies the Service uses.
    /// @dev Triggers `onRestake` on the Service.
    function restake(uint256 amountOrId, uint256 serviceId, uint256 commitUntil) external {
        require(amountOrId != 0, "Invalid amount or ID");
        require(serviceId <= _serviceCounter, "Invalid Service");
        require(commitUntil == 0 || commitUntil > block.timestamp, "Invalid commitment");
        require(
            !subscriptions[msg.sender].exists(serviceId) || commitUntil > subscriptions[msg.sender].viewCommitment(serviceId), "Commitment cannot be decreased"
        );

        // Resolve `commitUntil`.
        if (subscriptions[msg.sender].exists(serviceId)) {
            commitUntil = commitUntil != 0 ? commitUntil : subscriptions[msg.sender].viewCommitment(serviceId);
        }

        // Notify the Strategies that the Staker is restaking.
        // Reverting not allowed.
        // Note: We assume the Service trusts the Strategies not to revert by causing the call to run out of gas.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            uint8 maximumSlashingPercentage = serviceData[serviceId].maximumSlashingPercentages[strategyId];
            try strategyData[strategyId].strategy.onRestake(msg.sender, amountOrId, serviceId, commitUntil, maximumSlashingPercentage) {} catch {}
        }

        // Confirm the restaking with the Service.
        // The Service can revert.
        serviceData[serviceId].service.onRestake(msg.sender, amountOrId, commitUntil);

        // Activate a new subscription or extend the lock-in period of the existing one.
        subscriptions[msg.sender].track(serviceId, commitUntil);
    }

    // Review: Since we’re specifying the amount or ID to be unstaked, doesn’t the Staker also need to specify from which Strategy? Logically, yes - how else would they know what a random number means?
    // Review: Perhaps leave it to the Service to interpret and trigger Strategies? But this mean giving up the control to the Service.
    // Review: This also means the Staker would need to unstake via Strategies individualy. Add `unstakeAll` helper - however the case when the Staker unsubscribes by manually doing `unstake` also needs to be taken into account.
    // Review: Moreover, that'd also mean we need the Staker to specify the Strategy when restaking.
    // TODO: Init/fin: Announce if unsubscribing after committment ended (return true/false) [or always init OR perhaps force]. Important: Keep freezing in mind after annoucing. Also the case of slasher update - this needs to be resolved quicker.
    /// @notice Lets a Staker decrease their stake in a Service.
    /// @notice By unstaking the remaing amount of the stake, the Staker becomes unsubscribed from the Service, subject to the terms of the Service.
    /// @notice Lets the Staker decrease their stake immediately if the Service has scheduled a Slasher update.
    /// @param amountOrId Use `2**256 - 1` (`type(uint256).max`) to unstake the remaing amount of the stake.
    /// @dev Called by the Staker.
    /// @dev Triggers `onUnstake` on the Service.
    /// @dev Triggers `onUnstake` on all Strategies the Service uses.
    function unstake(uint256 serviceId, uint256 amountOrId) external {
        require(serviceId <= _serviceCounter, "Invalid service");
        require(subscriptions[msg.sender].exists(serviceId), "Not subscribed");
        require(!subscriptions[msg.sender].isFrozen(), "Cannot unstake while frozen");

        // Let the Staker unsubscribe if the Service has scheduled a Slasher update.
        // Reverting not allowed.
        // Note: We assume the Staker trusts the Service not to revert by causing the call to run out of gas.
        if (slasherUpdate[serviceId].newSlasher != address(0)) {
            try serviceData[serviceId].service.onUnstake(msg.sender, amountOrId) {} catch {}
        } else {
            // Confirm the unsubscription with the Service if the Staker is still committed.
            // The Service can revert.
            if (subscriptions[msg.sender].isCommitted(serviceId)) {
                serviceData[serviceId].service.onUnstake(msg.sender, amountOrId);
            } else {
                // Let the Staker unsubscribe if the Staker is no longer committed.
                // Notify the Service that the Staker has unsubscribed.
                // Reverting not allowed.
                // Note: We assume the Staker trusts the Service not to revert by causing the call to run out of gas.
                try serviceData[serviceId].service.onUnstake(msg.sender, amountOrId) {} catch {}
            }
        }

        // Notify the Strategies that the Staker has unsubscribed.
        // Reverting not allowed.
        // Note: We assume the Staker trust the Strategies not to revert by causing the call to run out of gas.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onUnstake(msg.sender, serviceId, amountOrId) {} catch {}
        }

        // Deactivate the subscription.
        if (amountOrId == type(uint256).max || ) subscriptions[msg.sender].stopTracking(serviceId);
    }

    // NOTE!!! Updated code up to this line. Some logic and docs below may be outdated! TODO

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

    /// @notice Temporarily prevents a Staker from unsubscribing from a Service.
    /// @notice This period can be used to prove the Staker should be slashed.
    /// @dev Called by a Slasher of the Service.
    function onFreeze(uint256 serviceId, address staker) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can freeze");

        // Note: We assume the Staker trusts the Service not to freeze them repeatedly.
        subscriptions[staker].freeze(serviceId, block.timestamp + STAKER_FREEZE_PERIOD);

        // Notify the Services that the Staker has been frozen.
        // Reverting not allowed.
        // TODO: We assume the Slasher trusts the Staker not to revert by causing the call to run out of gas. (!!!)
        // Answer: EVENT ONLY. Just an event for the adjustment requirement too (slashing)?
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
    // TODO Aggregation (see the new [private/not on GH] Note + make sure to clear all freezes)
    function onSlash(uint256 serviceId, address staker, SlashingInput[] calldata percentages) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can slash");
        require(subscriptions[staker].isFrozen(), "Staker not frozen");
        // TODO Do not allow duplicates. Do not allow Strategies not used.
        for (uint256 i; i < percentages.length; ++i) {
            SlashingInput calldata percentage = percentages[i];
            require(percentage.percentage <= serviceData[serviceId].maximumSlashingPercentages[percentage.strategyId], "Slashing percentage exceeds maximum");
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
            try strategyData[strategyId].strategy.onSlash(staker, percentage) {} catch {}
        }

        // Unfreeze the Staker.
        subscriptions[staker].unfreeze(serviceId);
    }

    // Review: Should a Service be able to unusubscribe a Staker?
    // Answer: Yes. at any moment
    /// @notice Ends a Staker's subscription with a Service.
    /// @dev Called by the Service.
    function unsubscribe(address staker) external {
        // TODO
    }

    // ========== QUERIES ==========

    /// @notice Tells if a Staker has active subscriptions.
    function hasSubscriptions(address staker) external view returns (bool) {
        return subscriptions[staker].hasSubscriptions();
    }

    /// @return exists Whether the Staker already has stake with the Service.
    /// @return committedUntil `0` if `exists` is `false`.
    function viewSubscription(address staker, uint256 serviceId) external view returns (bool exists, uint256 committedUntil) {
        exists = subscriptions[staker].exists(serviceId);
        committedUntil = exists ? subscriptions[staker].viewCommittment(serviceId) : 0;
    }
}

// Review: Need to think about what happens if, for example, a Strategy also registers as a Service that uses itself (the Strategy), and then subscribes to iteself, etc. If problematic, do not allow this.
