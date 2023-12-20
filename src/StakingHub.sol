// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Service} from "src/Service.sol";
import {Strategy} from "src/Strategy.sol";

/// @title Staking Hub
/// @author Polygon Labs
/// @notice The Hub is a permissionless place where Stakers and Services gather.
/// @notice The goal is to create new income streams for Stakers. Meanwhile, Services can acquire Stakers.
/// @notice Stakers can subscribe to Services (i.e., restake) via Strategies.
abstract contract StakingHub {
    struct ServiceData {
        Service service;
        uint256[] strategies;
        address slasher;
        uint8 maxSlashPercentage;
    }

    struct SlasherUpdate {
        address newSlasher;
        uint256 scheduledTime;
    }

    struct StrategyData {
        Strategy strategy;
    }

    uint256 private constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 private constant STAKER_FREEZE_TIME = 7 days;

    // Review: Do we really need IDs?
    uint256 private _strategyCounter;
    uint256 private _serviceCounter;

    mapping(address strategy => uint256 strategyId) public strategies;
    mapping(address service => uint256 serviceId) public services;

    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;
    mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdate;

    mapping(uint256 strategyId => StrategyData strategyData) public strategyData;

    // Review: Use linked list?
    mapping(address staker => uint256[] serviceIds) public subscriptions;
    mapping(address staker => mapping(uint256 serviceId => uint256 until)) public subscriptionEnd;

    mapping(address staker => mapping(uint256 serviceId => uint256 freezePeriodEnd)) freezeEnd;

    event StrategyRegistered(address indexed strategy, uint256 indexed strategyId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address newSlasher);

    /// @notice Adds a new Strategy to the Hub.
    /// @dev Called by the Strategy.
    function registerStrategy() external returns (uint256 id) {
        require(strategies[msg.sender] == 0, "Strategy already registered");

        id = ++_strategyCounter;
        strategies[msg.sender] = id;
        strategyData[id] = StrategyData(Strategy(msg.sender));
        emit StrategyRegistered(msg.sender, id);
    }

    /// @notice Adds a new Service to the Hub.
    /// @dev Called by the Service.
    function registerService(uint256[] calldata strategies_, address slasher, uint8 maxSlashPercentage) external returns (uint256 id) {
        require(strategies[msg.sender] == 0, "Service already registered");

        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id] = ServiceData(Service(msg.sender), strategies_, slasher, maxSlashPercentage);
        emit ServiceRegistered(msg.sender, id);
    }

    /// @notice Subscribes a Staker to a Service.
    /// @dev Called by the Staker.
    /// @dev Calls onSubscribe on all Strategies the Service uses.
    /// @dev Calls onSubscribe on the Service.
    function subscribe(uint256 serviceId, uint256 until) external {
        require(until > block.timestamp, "Invalid until");
        require(until > subscriptionEnd[msg.sender][serviceId], "Existing subscription not extended");

        subscriptions[msg.sender].push(serviceId);
        subscriptionEnd[msg.sender][serviceId] = until;

        // Alert the Strategies that the Staker has subscribed.
        // Reverting not allowed.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onSubscribe(msg.sender, serviceId, until) {} catch {}
        }

        // Confirm the subscription with the Service.
        // The Service can revert.
        serviceData[serviceId].service.onSubscribe(msg.sender, until);
    }

    /// @notice Unsubscribes a Staker from a Service.
    /// @dev Called by the Staker.
    /// @dev Calls onSubscribe on the Service.
    /// @dev Calls onSubscribe on all Strategies the Service uses.
    function unsubscribe(uint256 serviceId) external {
        require(subscriptionEnd[msg.sender][serviceId] <= block.timestamp, "Not subscribed");
        require(freezeEnd[msg.sender][serviceId] < block.timestamp, "Cannot unsubscribe while frozen");

        // Let the Staker unsubscribe if the Service has scheduled a Slasher update.
        // Reverting not allowed.
        if (slasherUpdate[serviceId].newSlasher != address(0)) {
            try serviceData[serviceId].service.onUnsubscribe(msg.sender) {} catch {}
        } else {
            // Confirm the unsubscription with the Service if the subscription hasn't expired.
            // The Service can revert.
            if (block.timestamp < subscriptionEnd[msg.sender][serviceId]) {
                serviceData[serviceId].service.onUnsubscribe(msg.sender);
            } else {
                // Do not let the Service hold the Staker hostage after the subscription has expired.
                // Alert the Service that the Staker has unsubscribed.
                // Reverting not allowed.
                try serviceData[serviceId].service.onUnsubscribe(msg.sender) {} catch {}
            }
        }

        // Alert the Strategies that the Staker has unsubscribed.
        // Reverting not allowed.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onUnsubscribe(msg.sender, serviceId) {} catch {}
        }

        for (uint256 i; i < subscriptions[msg.sender].length; ++i) {
            if (subscriptions[msg.sender][i] == serviceId) {
                delete subscriptions[msg.sender][i];
                break;
            }
        }
    }

    /// @notice Schedule a Slasher update for a Service.
    /// @dev Called by the Service.
    function initiateSlasherUpdate(address newSlasher) external returns (uint256 scheduledTime) {
        uint256 serviceId = services[msg.sender];
        SlasherUpdate storage update = slasherUpdate[serviceId];

        require(update.scheduledTime == 0, "Slasher update already initiated");

        scheduledTime = block.timestamp + SLASHER_UPDATE_TIMELOCK;

        update.newSlasher = newSlasher;
        update.scheduledTime = scheduledTime;

        emit SlasherUpdateInitiated(serviceId, newSlasher);
    }

    /// @notice Apply a scheduled Slasher update for a Service.
    /// @dev Called by the Service (or anyone).
    function finalizeSlasherUpdate() external {
        uint256 serviceId = services[msg.sender];
        SlasherUpdate storage update = slasherUpdate[serviceId];

        require(block.timestamp >= update.scheduledTime, "Slasher cannot be updated yet");

        serviceData[serviceId].slasher = update.newSlasher;

        delete slasherUpdate[services[msg.sender]];
    }

    /// @notice Temporarily prevents a Staker from unsubscribing from a Service.
    /// @notice This period can be used to prove the Staker should be slashed.
    /// @dev Called by a Slasher of the Service.
    function onFreeze(uint256 serviceId, address staker) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can freeze");

        // TODO How to validate?
        freezeEnd[staker][serviceId] = block.timestamp + STAKER_FREEZE_TIME;

        // Alert the Services that the Staker has been frozen.
        // Reverting not allowed.
        for (uint256 i; i < subscriptions[staker].length; ++i) {
            uint256 _serviceId = subscriptions[staker][i];
            if (_serviceId == 0) continue;
            try serviceData[_serviceId].service.onFreeze(staker) {} catch {}
        }
    }

    /// @notice Takes a portion of a Staker's funds away.
    /// @notice The Staker must be frozen first.
    /// @dev Called by a Slasher of a Service.
    /// @dev Calls onSlash on all Strategies the Services uses.
    function onSlash(uint256 serviceId, address staker, uint8 slashPercentage) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can slash");
        require(freezeEnd[staker][serviceId] > block.timestamp, "Staker not frozen");
        require(slashPercentage <= serviceData[serviceId].maxSlashPercentage, "Slash percentage exceeds the maximum");

        // Alert the Strategies that the Staker has been slashed.
        // Reverting not allowed.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onSlash(staker, slashPercentage) {} catch {}
        }

        // Unfreeze the Staker.
        freezeEnd[staker][serviceId] = 0;
    }
}
