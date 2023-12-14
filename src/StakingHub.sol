// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Service} from "src/Service.sol";
import {Strategy} from "src/Strategy.sol";

/// @title Staking Hub
/// @author Polygon Labs
/// @notice Staking Hub is a permissionless hub where Stakers and Services gather.
/// @notice The goal is to create new income streams for Stakers. Meanwhile, Services can acquire stakers.
/// @notice Stakers can subscribe to Services (i.e. restake) via Strategies.
abstract contract StakingHub {
    struct ServiceData {
        Service service;
        uint256[] strategies;
        address slasher;
        uint256 slashingPercentage;
    }

    struct StrategyData {
        Strategy strategy;
    }

    uint256 private _strategyCounter;
    uint256 private _serviceCounter;

    mapping(address strategy => uint256 id) public strategies;
    mapping(address service => uint256 id) public services;

    mapping(uint256 id => ServiceData serviceData) public serviceData;
    mapping(address validator => mapping(uint256 serviceId => bool isSubscribed)) public subscribedToService;
    mapping(address validator => uint256[] services) public subscribedServices;

    mapping(uint256 id => StrategyData strategyData) public strategyData;

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
    function registerService(uint256[] calldata strategies_, address slasher, uint256 slashingPercentage) external returns (uint256 id) {
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id] = ServiceData({service: Service(msg.sender), strategies: strategies_, slasher: slasher, slashingPercentage: slashingPercentage});
        emit ServiceRegistered(msg.sender, id);
    }

    /// @notice Subscribes to a Service.
    /// @dev Called by a Staker.
    function subscribe(uint256 serviceId, uint256 until) external {
        require(!subscribedToService[msg.sender][serviceId], "Already subscribed");
        require(until > block.timestamp, "Invalid until");

        subscribedToService[msg.sender][serviceId] = true;
        subscribedServices[msg.sender].push(serviceId);

        // Alert strategies that the Stake has been subscribed
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            strategyData[strategyId].strategy.onSubscribe(msg.sender, serviceId, until);
        }

        serviceData[serviceId].service.onSubscribe(msg.sender, until);
    }

    /// @notice Unsubscribes from a Service.
    /// @dev Called by a Staker.
    function unsubscribe(address service) external {
        /* if (block.timestamp < unil) {
            service.onUnsubscribe()
        } else {
            revert AlreadyUnsubscribed()?
        }
        // unsusbscribe logic*/
    }

    // 1. ISlasher.validateFreeze()
    // 2. Call service and announce that validator is frozen
    function onFreeze(uint256 serviceId, address staker) external {
        // Alert strategies that the Staker has been frozen
        for (uint256 i; i < serviceData[serviceId].strategies.length; ++i) {
            uint256 strategyId = serviceData[serviceId].strategies[i];
            try strategyData[strategyId].strategy.onFreeze(staker) {} catch {}
        }
    }

    // 1. service.validateSlashing()
    // 1.1 check how much to slash
    function onSlash(uint256 service, address validator, uint16 percentage) external {
        // TODO
    }
}
