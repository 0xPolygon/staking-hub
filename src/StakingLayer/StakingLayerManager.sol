// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";

import {IStrategy} from "../interface/IStrategy.sol";

import {StakingLayerStorage} from "./StakingLayerStorage.sol";
import {PackedUints} from "../lib/PackedUints.sol";

struct UnstakingNotice {
    uint256[] amountsOrIds;
    uint256 scheduledTime;
}

struct SlashingInput {
    uint256 strategyId;
    uint8 percentage;
}

struct ServiceData {
    IService service;
    uint256[] strategies;
    uint256 slashingPercentages;
    uint256 unstakingNoticePeriod;
    mapping(address staker => UnstakingNotice unstakingNotice) unstakingNotice; // TODO Convert to queue per service (context: the current system allows the Staker only one unstaking notice at a time per Service)
    address slasher; // Review: Can multiple Services use the same Slasher? If so, we'll need some guardrails.
    uint256 lastSlasherUpdate;
}

contract StakingLayerManager is StakingLayerStorage {
    using PackedUints for uint256;

    uint256 internal _strategyCounter;
    uint256 internal _serviceCounter;

    mapping(address strategy => uint256 strategyId) public strategies;
    mapping(address service => uint256 serviceId) public services;
    mapping(uint256 strategyId => IStrategy strategy) public strategyAddresses;
    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;

    /// @notice Adds a new Strategy to the Hub.
    /// @dev Called by the Strategy.
    function registerStrategy() external returns (uint256 id) {
        require(strategies[msg.sender] == 0, "Strategy already registered");

        // Add the Strategy.
        id = ++_strategyCounter;
        strategies[msg.sender] = id;
        strategyAddresses[id] = IStrategy(msg.sender);

        emit StrategyRegistered(msg.sender, id);
    }

    /// @notice Adds a new Service to the Hub.
    /// @param strategies_.percentage Use `0` or `100` for ERC-721 tokens.
    /// @dev Called by the Service.
    function registerService(SlashingInput[] calldata strategies_, uint256 unstakingNoticePeriod, address slasher) external returns (uint256 id) {
        require(services[msg.sender] == 0, "Service already registered");
        require(strategies_.length < 33, "Limit Strategies to 32");
        _validateStrategyInputs(strategies_);

        // Add the Service.
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id].service = IService(msg.sender);
        uint256 slashingPercentages;
        for (uint256 i; i < strategies_.length; ++i) {
            serviceData[id].strategies.push(strategies_[i].strategyId);
            slashingPercentages = slashingPercentages.set(strategies_[i].percentage, i);
        }
        serviceData[id].slashingPercentages = slashingPercentages;
        serviceData[id].unstakingNoticePeriod = unstakingNoticePeriod;
        serviceData[id].slasher = slasher;

        emit ServiceRegistered(msg.sender, id);
    }

    /// @dev Reverts if a Strategy does not exist, or a duplicate is found.
    /// @dev strategy ids must be sorted in ascending order for duplicate check
    function _validateStrategyInputs(SlashingInput[] calldata strategies_) internal view {
        uint256 lastId;
        uint256 len = strategies_.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 strategyId = strategies_[i].strategyId;
            require(strategyId > lastId, "Duplicate Strategy or Unsorted List");
            require(strategies_[i].percentage <= 100, "Invalid slashing percentage");
        }
        require(lastId <= _strategyCounter, "Invalid Strategy");
    }
}
