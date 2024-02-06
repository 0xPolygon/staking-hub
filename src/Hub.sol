// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IService} from "./interface/IService.sol";
import {ILocker} from "./interface/ILocker.sol";
import {Subscriptions, SubscriptionsStd} from "./lib/SubscriptionsStd.sol";
import {PackedUints} from "./lib/PackedUints.sol";

// TODO: Update docs.
// TODO: Double-check all `block.timestamp` conditions are correct (e.g., >= vs <).
/// @title Polygon Hub
/// @author Polygon Labs
/// @notice The Hub is a permissionless place where Stakers and Services gather.
/// @notice The goal is to create new income streams for Stakers. Meanwhile, Services can acquire Stakers.
/// @notice Stakers can subscribe to Services by restaking via Lockers.
contract Hub {
    // ========== DATA TYPES ==========

    using PackedUints for uint256;
    using SubscriptionsStd for Subscriptions;

    // Review: Do we want to allow Services to update thier `lockers`, `unstakingNoticePeriod`?
    struct ServiceData {
        IService service;
        uint256[] lockers;
        uint256 slashingPercentages;
        uint256 unstakingNoticePeriod;
        mapping(address staker => UnstakingNotice unstakingNotice) unstakingNotice; // TODO Convert to queue per service (context: the current system allows the Staker only one unstaking notice at a time per Service)
        address slasher; // Review: Can multiple Services use the same Slasher? If so, we'll need some guardrails.
        uint256 lastSlasherUpdate;
    }

    struct UnstakingNotice {
        uint256[] lockerIds;
        uint256[] amountsOrIds;
        uint256 scheduledTime;
    }

    struct SlasherUpdate {
        address newSlasher;
        uint256 scheduledTime;
    }

    struct SlashingInput {
        uint256 lockerId;
        uint8 percentage;
    }

    struct LockerData {
        ILocker locker;
    }
    // ========== PARAMETERS ==========

    // TODO: These are placeholders.
    uint256 private constant SERVICE_UNSTAKE_GAS = 500_000;
    uint256 private constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 private constant STAKER_FREEZE_PERIOD = 7 days;

    // ========== INTERNAL RECORDS ==========

    uint256 private _lockerCounter;
    uint256 private _serviceCounter;

    // ========== SERVICE & STRATEGY DATA ==========

    mapping(address locker => uint256 lockerId) public lockers;
    mapping(address service => uint256 serviceId) public services;

    mapping(uint256 serviceId => ServiceData serviceData) public serviceData;
    mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdates;

    mapping(uint256 lockerId => LockerData lockerData) public lockerData;

    // ========== STAKER DATA ==========

    mapping(address staker => Subscriptions subscriptions) public subscriptions;

    // ========== EVENTS ==========

    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event RestakingError(uint256 indexed lockerId, address indexed staker, bytes data);
    event UnstakingParametersIgnored();
    event UnstakingError(uint256 indexed serviceOrLockerId, address indexed staker, bytes data); // Review: May need to change `serviceOrLockerId` to the address so they can be differentiated in case the IDs are the same.
    event StakerFrozen(address indexed staker, uint256 serviceId);
    event SlashingError(uint256 indexed lockerId, address indexed slasher, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);

    // ========== ACTIONS ==========

    /// @notice Adds a new Locker to the Hub.
    /// @dev Called by the Locker.
    function registerLocker() external returns (uint256 id) {
        require(lockers[msg.sender] == 0, "Locker already registered");

        // Add the Locker.
        id = ++_lockerCounter;
        lockers[msg.sender] = id;
        lockerData[id].locker = ILocker(msg.sender);

        emit LockerRegistered(msg.sender, id);
    }

    /// @notice Adds a new Service to the Hub.
    /// @param lockers_.percentage Use `0` or `100` for ERC-721 tokens.
    /// @dev Called by the Service.
    function registerService(SlashingInput[] calldata lockers_, uint256 unstakingNoticePeriod, address slasher) external returns (uint256 id) {
        require(services[msg.sender] == 0, "Service already registered");
        require(lockers_.length < 33, "Limit Lockers to 32");
        _validateLockerInputs(lockers_);

        // Add the Service.
        id = ++_serviceCounter;
        services[msg.sender] = id;
        serviceData[id].service = IService(msg.sender);
        uint256 slashingPercentages;
        for (uint256 i; i < lockers_.length; ++i) {
            serviceData[id].lockers.push(lockers_[i].lockerId);
            slashingPercentages = slashingPercentages.set(lockers_[i].percentage, i);
        }
        serviceData[id].slashingPercentages = slashingPercentages;
        serviceData[id].unstakingNoticePeriod = unstakingNoticePeriod;
        serviceData[id].slasher = slasher;

        emit ServiceRegistered(msg.sender, id);
    }

    // TODO Service-specific freezing, not global.

    /// @notice Lets a Staker reuse funds they have previously deposited into Lockers used by a Service to increase their stake in that Service.
    /// @notice By restaking, the Staker becomes subscribed to the Service. Subscription terms are defined in the Service's contract.
    /// @notice Restaking may increase the Staker's commitment to the Service if the Staker is already subscribed to the Service. This depends on the `commitUntil` parameter.
    /// @param commitUntil You may pass `0` to indicate no change in commitment. `commitUntil` will always be resolved before notifying the Service and Lockers.
    /// @dev Called by the Staker.
    /// @dev Triggers `onRestake` on all Lockers the Service uses.
    /// @dev Triggers `onRestake` on the Service.
    /// @dev The subscription is updated at the end. The Lockers and Service may query `viewSubscription` to get the details of the current subscription the Staker has with the Service.
    function restake(uint256 serviceId, uint256[] calldata amountsOrIds, uint256 commitUntil) external {
        require(serviceId <= _serviceCounter, "Invalid Service");
        uint256[] memory lockerIds = serviceData[serviceId].lockers;
        require(amountsOrIds.length == lockerIds.length, "Invalid amountsOrIds");
        require(commitUntil == 0 || commitUntil > block.timestamp, "Invalid commitment");
        require(
            commitUntil == 0 || !subscriptions[msg.sender].exists(serviceId) || commitUntil > subscriptions[msg.sender].viewCommitment(serviceId),
            "Commitment cannot be decreased"
        );

        // Resolve `commitUntil`.
        if (subscriptions[msg.sender].exists(serviceId)) {
            commitUntil = commitUntil != 0 ? commitUntil : subscriptions[msg.sender].viewCommitment(serviceId);
        }

        // Notify the Lockers that the Staker is restaking.
        // Reverting not allowed.
        // Note: We assume the Service trusts the Lockers not to revert by causing the call to run out of gas.
        for (uint256 i; i < lockerIds.length; ++i) {
            uint256 maximumSlashingPercentages = serviceData[serviceId].slashingPercentages;
            try lockerData[lockerIds[i]].locker.onRestake(msg.sender, amountsOrIds[i], serviceId, commitUntil, maximumSlashingPercentages.get(i)) {}
            catch (bytes memory data) {
                emit RestakingError(lockerIds[i], msg.sender, data);
            }
        }

        // Confirm the restaking with the Service.
        // The Service can revert.
        serviceData[serviceId].service.onRestake(msg.sender, lockerIds, amountsOrIds, commitUntil);

        // Activate a new subscription or extend the lock-in period of the existing one.
        subscriptions[msg.sender].track(serviceId, commitUntil);
    }

    /// @notice Lets a Staker decrease their stake in a Service.
    /// @notice By unstaking the remaing amount of the stake, the Staker will get unsubscribed from the Service. Unsubscription terms are defined in the Service's contract.
    /// @notice Lets the Staker initiate the unstaking proccess from a Service if the Service requires unstaking notice.
    /// @notice Lets the Staker unstake immediately if a) the Service does not require unstaking notice; b) the Staker has given unstaking notice and the unstaking notice period has passed; c) the Service lets the Staker unstake anyway.
    /// @notice Additionaly, lets the Staker unstake immediately if the Service has scheduled a Slasher update or the last Slasher update was less then 7 days ago.
    /// @param amountsOrIds You may pass `2**256 - 1` (`type(uint256).max`) to unstake the remaing amount of the stake.
    /// @param amountsOrIds Will be ignored if the Service required unstaking notice and you are finalizing the unstaking now.
    /// @return finalized Whether the unstaking was finalized, or only initiated.
    /// @return finalizationTime The time at which the unstaking was finalized (`block.timestamp`), or will become finalizable.
    /// @dev Called by the Staker.
    /// @dev Triggers `onUnstake` on the Service.
    /// @dev Triggers `onUnstake` on all Lockers the Service uses.
    /// @dev The subscription is updated at the end. The Lockers and Service may query `viewSubscription` to get the details of the current subscription the Staker has with the Service.
    function unstake(uint256 serviceId, uint256[] calldata amountsOrIds) external returns (bool finalized, uint256 finalizationTime) {
        require(subscriptions[msg.sender].exists(serviceId), "Not subscribed");
        uint256[] memory lockerIds = serviceData[serviceId].lockers;
        require(amountsOrIds.length == lockerIds.length, "Invalid amountsOrIds");
        require(!subscriptions[msg.sender].isFrozen(), "Cannot unstake while frozen");

        // Determine whether to initiate the unstaking (i.e., give unstaking notice) or finalize the unstaking.
        if (serviceData[serviceId].unstakingNoticePeriod != 0) {
            // Initiate the unstaking if the Service requires unstaking notice and the Staker has not given one,
            // or finalize the unstaking if the Service has scheduled a Slasher update or the last Slasher update was less than 7 days ago.
            if (serviceData[serviceId].unstakingNotice[msg.sender].lockerIds.length == 0) {
                if (slasherUpdates[serviceId].newSlasher == address(0) && serviceData[serviceId].lastSlasherUpdate < block.timestamp - 7 days) {
                    return _initiateUnstaking(serviceId, lockerIds, amountsOrIds);
                } else {
                    return _finalizeUnstaking(serviceId, lockerIds, amountsOrIds, true);
                }
            } else {
                // Finalize the unstaking if the Service requires unstaking notice and the Staker has given one.
                if (lockerIds.length > 0) emit UnstakingParametersIgnored();
                return _finalizeUnstaking(
                    serviceId,
                    serviceData[serviceId].unstakingNotice[msg.sender].lockerIds,
                    serviceData[serviceId].unstakingNotice[msg.sender].amountsOrIds,
                    false
                );
            }
        } else {
            // Finalize the unstaking if the Service does not require unstaking notice.
            if (lockerIds.length > 0) emit UnstakingParametersIgnored();
            return _finalizeUnstaking(
                serviceId, serviceData[serviceId].unstakingNotice[msg.sender].lockerIds, serviceData[serviceId].unstakingNotice[msg.sender].amountsOrIds, false
            );
        }
    }

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

        delete slasherUpdates[serviceId];
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
    /// @dev Calls onSlash on all Lockers the Services uses.
    // TODO Aggregation (see the new [private/not on GH] Note + make sure to clear all freezes)
    function onSlash(uint256 serviceId, address staker, SlashingInput[] calldata percentages) external {
        require(msg.sender == serviceData[serviceId].slasher, "Only Slasher can slash");
        require(subscriptions[staker].isFrozen(), "Staker not frozen");
        uint256 maxSlashingPercentages = serviceData[serviceId].slashingPercentages;
        // TODO Do not allow duplicates. Do not allow Lockers not used.
        for (uint256 i; i < percentages.length; ++i) {
            SlashingInput calldata percentage = percentages[i];
            require(percentage.percentage <= maxSlashingPercentages.get(i), "Slashing percentage exceeds maximum");
        }

        // Notify all Lockers used by the Service that the Staker has been slashed.
        // Reverting not allowed.
        // TODO: We assume the Service trusts the Lockers not to revert by causing the call to run out of gas.
        for (uint256 i; i < serviceData[serviceId].lockers.length; ++i) {
            uint256 lockerId = serviceData[serviceId].lockers[i];
            uint256 percentage;
            // Review: Gas-inefficient check.
            for (uint256 j; j < percentages.length; ++j) {
                if (percentages[j].lockerId == lockerId) {
                    percentage = percentages[j].percentage;
                    break;
                }
            }
            // TODO: locker expects amount, not percentage
            try lockerData[lockerId].locker.onSlash(staker, serviceId, percentage) {}
            catch (bytes memory data) {
                emit SlashingError(lockerId, msg.sender, staker, data);
            }
        }

        // Unfreeze the Staker.
        subscriptions[staker].unfreeze(serviceId);
    }

    function onUnfreeze(uint256 serviceId, address staker) external {
        // TODO Add onUnfreeze
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
        committedUntil = exists ? subscriptions[staker].viewCommitment(serviceId) : 0;
    }

    // ========== HELPERS ==========

    /// @dev Reverts if Locker IDs and the other inputs are not of the same length, a Locker does not exist, or an other input is invalid.
    /// @dev locker ids must be sorted in ascending order for duplicate check
    function _validateLockerInputs(SlashingInput[] calldata lockers_) internal view {
        uint256 lastId;
        uint256 len = lockers_.length;
        for (uint256 i = 0; i < len; ++i) {
            uint256 lockerId = lockers_[i].lockerId;
            require(lockerId > lastId, "Duplicate Locker or Unsorted List");
            require(lockers_[i].percentage <= 100, "Invalid slashing percentage");
        }
        require(lastId <= _lockerCounter, "Invalid Locker");
    }

    function _initiateUnstaking(uint256 serviceId, uint256[] memory lockerIds, uint256[] calldata amountsOrIds)
        internal
        returns (bool finalized, uint256 finalizationTime)
    {
        // The Service may choose to let the Staker unstake immediately, even when the notice period has not passed.
        bool finalizeImmediately;

        // Confirm the unstaking with the Service if the Staker will still be committed when the unstaking notice period has passed.
        // The Service can revert.
        if (subscriptions[msg.sender].viewCommitment(serviceId) + serviceData[serviceId].unstakingNoticePeriod > block.timestamp) {
            finalizeImmediately = serviceData[serviceId].service.onInitializeUnstaking(msg.sender, lockerIds, amountsOrIds);
        } else {
            // Let the Staker initiate unstaking if the Staker is no longer committed, or will no longer be committed after the unstaking notice period has passed.
            // Notify the Service that the Staker has unstaked.
            // Reverting not allowed.
            try serviceData[serviceId].service.onInitializeUnstaking{gas: SERVICE_UNSTAKE_GAS}(msg.sender, lockerIds, amountsOrIds) returns (
                bool finalizeImmediately_
            ) {
                finalizeImmediately = finalizeImmediately_;
            } catch (bytes memory data) {
                emit UnstakingError(serviceId, msg.sender, data);
            }
        }

        // Finalize the unstaking if the Service chose to let the Staker unstake immediately.
        if (finalizeImmediately) return _finalizeUnstaking(serviceId, lockerIds, amountsOrIds, true);

        // Schedule the unstaking.
        uint256 scheduledTime = block.timestamp + serviceData[serviceId].unstakingNotice[msg.sender].scheduledTime;
        serviceData[serviceId].unstakingNotice[msg.sender] = UnstakingNotice(lockerIds, amountsOrIds, scheduledTime);

        return (false, scheduledTime);
    }

    function _finalizeUnstaking(uint256 serviceId, uint256[] memory lockerIds, uint256[] memory amountsOrIds, bool force)
        internal
        returns (bool finalized, uint256 finalizationTime)
    {
        if (!force) {
            require(
                serviceData[serviceId].unstakingNotice[msg.sender].scheduledTime != 0
                    && serviceData[serviceId].unstakingNotice[msg.sender].scheduledTime <= block.timestamp || serviceData[serviceId].unstakingNoticePeriod == 0,
                "You must announce unstaking first"
            );
        }

        // Notify the Service that the Staker is unstaking.
        // Reverting not allowed.
        try serviceData[serviceId].service.onFinalizeUnstaking{gas: SERVICE_UNSTAKE_GAS}(msg.sender, lockerIds, amountsOrIds) {}
        catch (bytes memory data) {
            emit UnstakingError(serviceId, msg.sender, data);
        }

        // Review: Should we allow Lockers to revert here?
        // Notify the Lockers that the Staker has unstaked.
        // Reverting not allowed.
        // Note: We assume the Staker trust the Lockers not to revert by causing the call to run out of gas.
        for (uint256 i; i < lockerIds.length; ++i) {
            try lockerData[lockerIds[i]].locker.onUnstake(msg.sender, serviceId, amountsOrIds[i]) {}
            catch (bytes memory data) {
                emit UnstakingError(lockerIds[i], msg.sender, data);
            }
        }

        // Deactivate the subscription if the Staker doesn't have any more stake in the Service.
        // Note: We assume the Service, which use the Lockers, trust them to report the Staker's balance in the Service correctly.
        // Note: We assume the Staker trust the Lockers not to revert by causing the call to run out of gas.
        bool stakeIsZero = true;
        for (uint256 i; i < serviceData[serviceId].lockers.length; ++i) {
            try lockerData[serviceData[serviceId].lockers[i]].locker.balanceOfIn(msg.sender, serviceId) returns (uint256 balanceOfInService) {
                if (balanceOfInService != 0) stakeIsZero = false;
            } catch {}
        }
        if (stakeIsZero) subscriptions[msg.sender].stopTracking(serviceId);

        // Remove the unstaking notice.
        delete serviceData[serviceId].unstakingNotice[msg.sender];

        return (true, block.timestamp);
    }
}

// Review: What happens if, for example, a Locker also registers as a Service that uses itself (the Locker), and then subscribes to iteself, etc. We'll probably disallow this.
// Review: Similarly with Stakers and Slashers.
