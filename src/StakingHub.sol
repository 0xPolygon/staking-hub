// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Service} from "src/Service.sol";
import {Strategy} from "src/Strategy.sol";

/// @title Staking Hub
/// @author Polygon Labs
/// @notice Hub is a permissionless place where Stakers and Services gather.
/// @notice The goal is to create new income streams for Stakers. Meanwhile, Services can acquire Stakers.
/// @notice Stakers can Subscribe to Services (i.e. restake) via Strategies.
abstract contract StakingHub {
    struct ServiceData {
        Service service;
        uint256[] strategies;
        address slasher;
        uint8 maxSlashPercentage;
    }

    struct SlasherUpdate {
        address newSlasher;
        uint256 time;
    }

    struct StrategyData {
        Strategy strategy;
    }

    uint256 public constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 public constant STAKER_FREEZE_TIME = 7 days;

    uint256 private _strategyCounter;
    uint256 private _serviceCounter;

    mapping(address strategy => uint256 strategyId) public strategies;
    mapping(address service => uint256 serviceId) public services;

    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;
    mapping(address staker => mapping(uint256 serviceId => uint256 until)) public subscribedToService;
    mapping(address staker => uint256[] serviceIds) public subscribedServices;

    mapping(uint256 strategyId => StrategyData strategyData) public strategyData;

    mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdate;

    mapping(address staker => mapping(uint256 serviceId => uint256 freezePeriodEnd)) freezes;

    event StrategyRegistered(address indexed strategy, uint256 indexed id);
    event ServiceRegistered(address indexed service, uint256 indexed id);

    /// @notice Adds a new strategy.
    /// @dev Called by a Strategy.
    function registerStrategy() external returns (uint256 id) {
        id = ++_strategyCounter;
        strategies[msg.sender] = id;
        strategyData[id] = StrategyData({strategy: Strategy(msg.sender)});
        emit StrategyRegistered(msg.sender, id);
    }

    /// @notice Adds a new Service.
    /// @dev Called by a Service.
    function registerService(uint256[] calldata strategies_, address slasher, uint8 maxSlashPercentage) external returns (uint256 id) {
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id] = ServiceData({service: Service(msg.sender), strategies: strategies_, slasher: slasher, maxSlashPercentage: maxSlashPercentage});
        emit ServiceRegistered(msg.sender, id);
    }

    /// @notice Subscribes to a Service.
    /// @dev Called by a Staker.
    function subscribe(uint256 serviceId, uint256 until) external {
        require(until > subscribedToService[msg.sender][serviceId], "Subscription not extended");
        require(until > block.timestamp, "Invalid until");

        subscribedToService[msg.sender][serviceId] = until;
        subscribedServices[msg.sender].push(serviceId);

        // Alert strategies that the Staker has subscribed
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onSubscribe(msg.sender, serviceId, until) {} catch {}
        }

        serviceData[serviceId].service.onSubscribe(msg.sender, until);
    }

    /// @notice Unsubscribes from a Service.
    /// @dev Called by a Staker.
    function unsubscribe(uint256 serviceId) external {
        require(subscribedToService[msg.sender][serviceId] <= block.timestamp, "Not subscribed");
        require(freezes[msg.sender][serviceId] < block.timestamp, "Frozen");

        // If slasher update initiated, do not let the Service revert
        if (slasherUpdate[serviceId].newSlasher != address(0)) {
            try serviceData[serviceId].service.onUnsubscribe(msg.sender) {} catch {}
        }
        // If before Until, let the Service revert
        else {
            if (block.timestamp < subscribedToService[msg.sender][serviceId]) {
                serviceData[serviceId].service.onUnsubscribe(msg.sender);
            }
        }

        // Auto unsubscribe after until, so Service can't hold Staker hostage
        // Alert strategies that the Staker has unsubscribed
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onUnsubscribe(msg.sender, serviceId) {} catch {}
        }

        // Update records
        for (uint256 i; i < subscribedServices[msg.sender].length; ++i) {
            if (subscribedServices[msg.sender][i] == serviceId) {
                delete subscribedServices[msg.sender][i];
                break;
            }
        }
        //subscribedToService[msg.sender][serviceId] = 0;
    }

    /// @notice Initiate Slasher update.
    /// @dev Called by a Service.
    function initiateSlasherUpdate(address newSlasher) external returns (uint256 time) {
        SlasherUpdate storage update = slasherUpdate[services[msg.sender]];

        require(update.time == 0, "Slasher update already initiated");

        time = block.timestamp + SLASHER_UPDATE_TIMELOCK;

        update.newSlasher = newSlasher;
        update.time = time;
    }

    /// @notice Finalize a Slasher update.
    /// @dev Called by a Service.
    function finalizeSlasherUpdate() external {
        uint256 serviceId = services[msg.sender];
        SlasherUpdate storage update = slasherUpdate[serviceId];

        require(block.timestamp >= update.time, "Slasher cannot be updated yet");

        serviceData[serviceId].slasher = update.newSlasher;

        delete slasherUpdate[services[msg.sender]];
    }

    /// @dev Called by a Slasher;
    function onFreeze(uint256 serviceId, address staker) external {
        require(msg.sender == serviceData[serviceId].slasher);

        // TODO Validation?
        freezes[staker][serviceId] = block.timestamp + STAKER_FREEZE_TIME;

        /*for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onFreeze(staker) {} catch {}
        }*/

        // Alert Services that the Staker has been frozen (onFreeze).
        // Reverting not allowed.
        for (uint256 i; i < subscribedServices[staker].length; ++i) {
            uint256 _serviceId = subscribedServices[staker][i];
            try serviceData[_serviceId].service.onFreeze(staker) {} catch {}
        }
    }

    /// @dev Called by a Slasher.
    function onSlash(uint256 serviceId, address staker, uint8 slashPercentage) external {
        require(msg.sender == serviceData[serviceId].slasher);
        require(freezes[staker][serviceId] > block.timestamp, "Staker not frozen");
        require(slashPercentage <= serviceData[serviceId].maxSlashPercentage);

        // Alert strategies that the Staker has been slashed (onSlash).
        // Reverting not allowed.
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onSlash(staker, slashPercentage) {} catch {}
        }

        freezes[staker][serviceId] = 0;
    }
}
