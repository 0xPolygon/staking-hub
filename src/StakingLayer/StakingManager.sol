// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {StakingLayerManager, UnstakingNotice} from "./StakingLayerManager.sol";
import {Subscriptions, SubscriptionsStd} from "../lib/SubscriptionsStd.sol";
import {PackedUints} from "../lib/PackedUints.sol";

contract StakingManager is StakingLayerManager {
    using PackedUints for uint256;
    using SubscriptionsStd for Subscriptions;

    mapping(address staker => Subscriptions subscriptions) public subscriptions;

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
            try lockerAddresses[lockerIds[i]].onRestake(msg.sender, amountsOrIds[i], serviceId, commitUntil, maximumSlashingPercentages.get(i)) {}
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
            if (serviceData[serviceId].unstakingNotice[msg.sender].amountsOrIds.length == 0) {
                if (slasherUpdates[serviceId].newSlasher == address(0) && serviceData[serviceId].lastSlasherUpdate < block.timestamp - 7 days) {
                    return _initiateUnstaking(serviceId, lockerIds, amountsOrIds);
                } else {
                    return _finalizeUnstaking(serviceId, lockerIds, amountsOrIds, true);
                }
            } else {
                // Finalize the unstaking if the Service requires unstaking notice and the Staker has given one.
                if (lockerIds.length > 0) emit UnstakingParametersIgnored();
                return _finalizeUnstaking(serviceId, serviceData[serviceId].unstakingNotice[msg.sender].amountsOrIds, false);
            }
        } else {
            // Finalize the unstaking if the Service does not require unstaking notice.
            if (lockerIds.length > 0) emit UnstakingParametersIgnored();
            return _finalizeUnstaking(serviceId, serviceData[serviceId].unstakingNotice[msg.sender].amountsOrIds, false);
        }
    }

    function _initiateUnstaking(uint256 serviceId, uint256[] calldata amountsOrIds) internal returns (bool finalized, uint256 finalizationTime) {
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
        serviceData[serviceId].unstakingNotice[msg.sender] = UnstakingNotice(amountsOrIds, scheduledTime);

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
            try lockerAddresses[lockerIds[i]].onUnstake(msg.sender, serviceId, amountsOrIds[i]) {}
            catch (bytes memory data) {
                emit UnstakingError(lockerIds[i], msg.sender, data);
            }
        }

        // Deactivate the subscription if the Staker doesn't have any more stake in the Service.
        // Note: We assume the Service, which use the Lockers, trust them to report the Staker's balance in the Service correctly.
        // Note: We assume the Staker trust the Lockers not to revert by causing the call to run out of gas.
        bool stakeIsZero = true;
        for (uint256 i; i < serviceData[serviceId].lockers.length; ++i) {
            try lockerAddresses[serviceData[serviceId].lockers[i]].balanceOfIn(msg.sender, serviceId) returns (uint256 balanceOfInService) {
                if (balanceOfInService != 0) stakeIsZero = false;
            } catch {}
        }
        if (stakeIsZero) subscriptions[msg.sender].stopTracking(serviceId);

        // Remove the unstaking notice.
        delete serviceData[serviceId].unstakingNotice[msg.sender];

        return (true, block.timestamp);
    }
}
