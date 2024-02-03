// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IService} from "./interface/IService.sol";
import {IStrategy} from "./interface/IStrategy.sol";
import {Subscriptions, SubscriptionsStd} from "./lib/SubscriptionsStd.sol";

// TODO: Update docs.
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
        mapping (uint256 strategyId => bool used) usesStrategy;
        mapping(uint256 strategyId => uint8 percentage) maximumSlashingPercentage;
        uint256 unstakeNoticePeriod;
        // TODO staker => strategyId => unstakingTime => amountOrId unstakingNotice;
        address slasher; // Review: Can multiple Services use the same Slasher? If so, we need to add some guardrails.
        uint256 lastSlasherUpdate;
    }

    struct StrategyData {
        IStrategy strategy;
    }

    struct SlasherUpdate {
        address newSlasher;
        uint256 scheduledTime;
    }

    // ========== PARAMETERS ==========

    // TODO: These are placeholders.
    uint256 private constant SERVICE_ONUNSTAKE_GAS = 500_000;
    uint256 private constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 private constant STAKER_FREEZE_PERIOD = 7 days;

    // ========== INTERNAL RECORDS ==========

    uint256 private _strategyCounter;
    uint256 private _serviceCounter;

    // ========== SERVICE & STRATEGY DATA ==========

    mapping(address strategy => uint256 strategyId) public strategies;
    mapping(address service => uint256 serviceId) public services;

    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;
    mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdates;

    mapping(uint256 strategyId => StrategyData strategyData) public strategyData;

    // ========== STAKER DATA ==========

    mapping(address staker => Subscriptions subscriptions) public subscriptions;

    // ========== EVENTS ==========

    event StrategyRegistered(address indexed strategy, uint256 indexed strategyId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event RestakingError(uint256 indexed strategyId, address indexed staker, bytes data);
    event UnstakingError(uint256 indexed strategyId, address indexed staker, bytes data);
    event SlashingError(uint256 indexed strategyId, address indexed slasher, address indexed staker, bytes data);
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
    /// @param maximumSlashingPercentages Use `0` or `100` for ERC-721 tokens.
    /// @dev Called by the Service.
    function registerService(uint256[] calldata strategies_, uint256[] calldata maximumSlashingPercentages, uint256 unstakeNoticePeriod, address slasher)
        external
        returns (uint256 id)
    {
        require(strategies[msg.sender] == 0, "Service already registered");
        for (uint256 i = 0; i < strategies_.length; ++i) {
            uint256 strategyId = strategies_[i];
            require(strategyId <= _strategyCounter, "Invalid Strategy");
            for (uint256 j = i + 1; j < strategies_.length; ++j) {
                require(strategyId != strategies_[j], "Duplicate Strategy");
            }
        }
        require(maximumSlashingPercentages.length == strategies_.length, "Invalid length of maximum slashing percetages");

        // Add the Service.
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id].service = IService(msg.sender);
        for (uint i; i < strategies_.length; ++i) {
            serviceData[id].strategies.push(strategies_[i]);
            serviceData[id].usesStrategy[strategies_[i]] = true;
            serviceData[id].maximumSlashingPercentage[strategies_[i]] = maximumSlashingPercentages[i];
        }
        serviceData[id].unstakeNoticePeriod = unstakeNoticePeriod;
        serviceData[id].slasher = slasher;

        emit ServiceRegistered(msg.sender, id);
    }

    /// @notice Lets a Staker reuse funds they have previously deposited into Strategies used by a Service to increase their stake in that Service.
    /// @notice By restaking, the Staker becomes subscribed to the Service, subject to the terms of the Service.
    /// @notice Restaking may increase the Staker's commitment to the Service if the Staker is already subscribed to the Service. This depends on the `commitUntil` parameter.
    /// @param commitUntil Use `0` to indicate no change in commitment. `commitUntil` will be resolved to a value before further processing.
    /// @dev Called by the Staker.
    /// @dev Triggers `onRestake` on all Strategies the Service uses.
    /// @dev Triggers `onRestake` on the Service.
    /// @dev The subscription is updated at the end. The Strategies and Service may query `viewSubscription` to get the details of the current subscription the Staker has with the Service.
    function restake(uint256 serviceId, uint256[] calldata strategyIds, uint256[] calldata amountsOrIds, uint256 commitUntil) external {
        require(serviceId <= _serviceCounter, "Invalid Service");
        require(amountsOrIds.length == strategies_.length, "Invalid length of amounts or IDs");
        for (uint256 i = 0; i < strategies_.length; ++i) {
            require(serviceData[serviceId].usesStrategy[strategyIds[i]], "Invalid Strategy");
            require(amountsOrIds[i] != 0, "Invalid amount or ID");
            for (uint256 j = i + 1; j < strategies_.length; ++j) {
                require(strategyIds[i] != strategyIds[j], "Duplicate Strategy");
            }
        }
        require(commitUntil == 0 || commitUntil > block.timestamp, "Invalid commitment");
        require(
            commitUntil == 0 || !subscriptions[msg.sender].exists(serviceId) || commitUntil > subscriptions[msg.sender].viewCommitment(serviceId), "Commitment cannot be decreased"
        );

        // Resolve `commitUntil`.
        if (subscriptions[msg.sender].exists(serviceId)) {
            commitUntil = commitUntil != 0 ? commitUntil : subscriptions[msg.sender].viewCommitment(serviceId);
        }

        // Notify the Strategies that the Staker is restaking.
        // Reverting not allowed.
        // Note: We assume the Service trusts the Strategies not to revert by causing the call to run out of gas.
        for (uint256 i; i < strategyIds.length; ++i) {
            uint8 maximumSlashingPercentage = serviceData[serviceId].maximumSlashingPercentage[strategyIds[i]];
            try strategyData[strategyIds[i]].strategy.onRestake(msg.sender, amountsOrIds[i], serviceId, commitUntil, maximumSlashingPercentage) {} catch (bytes memory data) {emit RestakingError(strategyIds[i], msg.sender, data);}
        }

        // Confirm the restaking with the Service.
        // The Service can revert.
        serviceData[serviceId].service.onRestake(msg.sender, strategyIds, amountsOrIds, commitUntil);

        // Activate a new subscription or extend the lock-in period of the existing one.
        subscriptions[msg.sender].track(serviceId, commitUntil);
    }

    /// @notice Lets a Staker initiate unstaking from a Service, if the Service requires a prior notice,
    /// @notice or unstake immediately, if the Service does not require a prior notice, the Staker has initiated unstaking and waited for the notice period to pass, or the Service lets the Staker unstake immediately.
    /// @return finalizedUnstaking Whether the unstaking was finalized, or only initiated.
    /// @return finalizationTime The time at which the unstaking was finalized, or will become finalizable.
    function unstake(uint256 serviceId, uint256[] calldata strategyIds, uint256[] calldata amountsOrIds) external returns (bool finalizedUnstaking, uint256 finalizationTime) {
        // TODO Read the NatSpec above.
    }

    function _initiateUnstaking() internal {
        // TODO
    }

    /// @notice Lets a Staker decrease their stake in a Service.
    /// @notice By unstaking the remaing amount of the stake, the Staker becomes unsubscribed from the Service, subject to the terms of the Service.
    /// @notice Lets the Staker decrease their stake immediately if the Service has scheduled a Slasher update or last update was less then 7 days ago.
    /// @param amountOrId Use `2**256 - 1` (`type(uint256).max`) to unstake the remaing amount of the stake.
    /// @dev Called by the Staker.
    /// @dev Triggers `onUnstake` on the Service.
    /// @dev Triggers `onUnstake` on all Strategies the Service uses.
    /// @dev The subscription is updated at the end. The Strategies and Service may query `viewSubscription` to get the details of the current subscription the Staker has with the Service.
    function _finalizeUnstaking(uint256 serviceId, uint256[] calldata strategyIds, uint256[] calldata amountsOrIds) internal {
        require(serviceId <= _serviceCounter, "Invalid Service");
        require(subscriptions[msg.sender].exists(serviceId), "Not subscribed");
        require(amountsOrIds.length == strategies_.length, "Invalid length of amounts or IDs");
        for (uint256 i = 0; i < strategies_.length; ++i) {
            require(serviceData[serviceId].usesStrategy[strategyIds[i]], "Invalid Strategy");
            require(amountsOrIds[i] != 0, "Invalid amount or ID");
            for (uint256 j = i + 1; j < strategies_.length; ++j) {
                require(strategyIds[i] != strategyIds[j], "Duplicate Strategy");
            }
        }
        require(!subscriptions[msg.sender].isFrozen(), "Cannot unstake while frozen");
        require(/*notice period passed*/ || serviceData[serviceId].unstakeNoticePeriod == 0, "You must announce unstaking first");

        // Let the Staker unsubscribe if the Service has scheduled a Slasher update or last update was less than 7 days ago.
        // Reverting not allowed.
        if (slasherUpdates[serviceId].newSlasher != address(0) || serviceData[serviceId].lastSlasherUpdate > block.timestamp - 7 days) {
            try serviceData[serviceId].service.onUnstake{gas: SERVICE_ONUNSTAKE_GAS}(msg.sender, strategyIds, amountsOrIds) {} catch {}
        } else {
            // Confirm the unsubscription with the Service if the Staker is still committed.
            // The Service can revert.
            if (subscriptions[msg.sender].isCommitted(serviceId)) {
                serviceData[serviceId].service.onUnstake(msg.sender, strategyIds, amountsOrIds);
            } else {
                // Let the Staker unsubscribe if the Staker is no longer committed.
                // Notify the Service that the Staker has unstaked.
                // Reverting not allowed.
                try serviceData[serviceId].service.onUnstake{gas: SERVICE_ONUNSTAKE_GAS}(msg.sender, strategyIds, amountsOrIds) {} catch {}
            }
        }

        // Review: Should we allow Strategies to revert here?
        // Notify the Strategies that the Staker has unstaked.
        // Reverting not allowed.
        // Note: We assume the Staker trust the Strategies not to revert by causing the call to run out of gas.
        for (uint256 i; i < strategyIds.length; ++i) {
            try strategyData[strategyIds[i]].strategy.onUnstake(msg.sender, serviceId, amountsOrIds[i]) {} catch (bytes memory data) {emit UnstakingError(strategyIds[i], msg.sender, data);}
        }

        // Deactivate the subscription if the Staker doesn't have any stake in the Service.
        // Note: We assume Services that use the Strategy trust it to report a Staker's balance in the Service honestly.
        // Note: We assume the Staker trust the Strategies not to revert by causing the call to run out of gas.
        bool stakeIsZero = true;
        for (uint i; i < serviceData[serviceId].strategies.length; ++i) {
            try strategyData[serviceData[serviceId].strategies[i]].strategy.balanceIn(msg.sender, serviceId) returns (uint256 balanceInService) {
                if (balanceInService != 0) stakeIsZero = false;
            } catch {}
        }
        if (stakeIsZero) subscriptions[msg.sender].stopTracking(serviceId);
    }

    // NOTE: Updated code throug this line. Some logic and docs below may be outdated! TODO

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
        // Answer: EVENT ONLY. Just an event for the adjustment requirement too (slashing)? - add a note regarding the attack vector so no one changes it!
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
            require(percentage.percentage <= serviceData[serviceId].maximumSlashingPercentage[percentage.strategyId], "Slashing percentage exceeds maximum");
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
            try strategyData[strategyId].strategy.onSlash(staker, percentage) {} catch (bytes memory data) {emit SlashingError(strategyId, msg.sender, staker, data);}
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

// Review: What happens if, for example, a Strategy also registers as a Service that uses itself (the Strategy), and then subscribes to iteself, etc. If problematic, do not allow this.
