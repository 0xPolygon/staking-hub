// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {StakingLayerManager, UnstakingNotice} from "./StakingLayerManager.sol";
import {Subscriptions, SubscriptionsStd} from "../lib/SubscriptionsStd.sol";
import {PackedUints} from "../lib/PackedUints.sol";
import {SlashingManager} from "./SlashingManager.sol";

contract StakingManager is SlashingManager {
    using PackedUints for uint256;
    using SubscriptionsStd for Subscriptions;

    /// @notice Lets a Staker reuse funds they have previously deposited into Lockers used by a Service to increase their stake in that Service.
    /// @notice By restaking, the Staker becomes subscribed to the Service. Subscription terms are defined in the Service's contract.
    /// @notice Restaking may increase the Staker's commitment to the Service if the Staker is already subscribed to the Service. This depends on the `commitUntil` parameter.
    /// @param commitUntil You may pass `0` to indicate no change in commitment. `commitUntil` will always be resolved before notifying the Service and Lockers.
    /// @dev Called by the Staker.
    /// @dev Triggers `onRestake` on all Lockers the Service uses.
    /// @dev Triggers `onRestake` on the Service.
    /// @dev For ERC721 staking, pass token id, for ERC1155 staking, encode amount and token id into single uint256
    function restake(uint256 serviceId, uint256[] calldata amounts, uint256 commitUntil) external {
        require(serviceId <= _serviceCounter, "Invalid Service");
        uint256[] memory lockerIds = serviceData[serviceId].lockers;
        require(amounts.length == lockerIds.length, "Invalid amounts");
        require(commitUntil == 0 || commitUntil > block.timestamp, "Invalid commitment");
        require(
            commitUntil == 0 || !subscriptions[msg.sender].exists(serviceId) || commitUntil > subscriptions[msg.sender].viewCommitment(serviceId),
            "Commitment cannot be decreased"
        );
        require(!subscriptions[msg.sender].isFrozen(), "Cannot unstake while frozen");

        // Resolve `commitUntil`.
        if (subscriptions[msg.sender].exists(serviceId)) {
            commitUntil = commitUntil != 0 ? commitUntil : subscriptions[msg.sender].viewCommitment(serviceId);
        }

        // Activate a new subscription or extend the lock-in period of the existing one.
        subscriptions[msg.sender].track(serviceId, commitUntil);

        // Notify the Lockers that the Staker is restaking.
        // Reverting not allowed.
        // Note: We assume the Service trusts the Lockers not to revert by causing the call to run out of gas.
        for (uint256 i; i < lockerIds.length; ++i) {
            uint256 maxSlashingPercentages = serviceData[serviceId].slashingPercentages;
            try lockerAddresses[lockerIds[i]].onRestake(msg.sender, serviceId, amounts[i], maxSlashingPercentages.get(i)) {}
            catch (bytes memory data) {
                emit RestakingError(lockerIds[i], msg.sender, data);
            }
        }

        // Confirm the restaking with the Service.
        // The Service can revert.
        serviceData[serviceId].service.onRestake(msg.sender);
    }

    function initiateUnstaking(uint256 serviceId, uint256[] calldata amounts) external {
        require(subscriptions[msg.sender].exists(serviceId), "Not subscribed");
        require(!subscriptions[msg.sender].isFrozen(), "Cannot unstake while frozen");
        // TODO
        uint256 scheduledTime = block.timestamp + serviceData[serviceId].unstakingNoticePeriod;
        if (_canUnstakeImmediately()) {
            scheduledTime = block.timestamp;
        }

        if (_initiateUnstaking(serviceId, amounts)) {
            scheduledTime = block.timestamp;
        }

        serviceData[serviceId].unstakingNotice[msg.sender] = UnstakingNotice(amounts, scheduledTime);
    }

    /// @notice Lets a Staker decrease their stake in a Service.
    /// @notice By unstaking the remaing amount of the stake, the Staker will get unsubscribed from the Service. Unsubscription terms are defined in the Service's contract.
    /// @notice Lets the Staker initiate the unstaking proccess from a Service if the Service requires unstaking notice.
    /// @notice Lets the Staker unstake immediately if a) the Service does not require unstaking notice; b) the Staker has given unstaking notice and the unstaking notice period has passed; c) the Service lets the Staker unstake anyway.
    /// @notice Additionaly, lets the Staker unstake immediately if the Service has scheduled a Slasher update or the last Slasher update was less then 7 days ago.
    /// @param amounts You may pass `2**256 - 1` (`type(uint256).max`) to unstake the remaing amount of the stake.
    /// @param amounts Will be ignored if the Service required unstaking notice and you are finalizing the unstaking now.
    /// @return finalized Whether the unstaking was finalized, or only initiated.
    /// @return finalizationTime The time at which the unstaking was finalized (`block.timestamp`), or will become finalizable.
    /// @dev Called by the Staker.
    /// @dev Triggers `onUnstake` on the Service.
    /// @dev Triggers `onUnstake` on all Lockers the Service uses.
    /// @dev The subscription is updated at the end. The Lockers and Service may query `viewSubscription` to get the details of the current subscription the Staker has with the Service.
    function finaliseUnstake(uint256 serviceId, uint256[] calldata amounts) external returns (bool finalized, uint256 finalizationTime) {
        require(subscriptions[msg.sender].exists(serviceId), "Not subscribed");
        require(!subscriptions[msg.sender].isFrozen(), "Cannot unstake while frozen");
        uint256 scheduledTime = serviceData[serviceId].unstakingNotice[msg.sender].scheduledTime;
        require(scheduledTime != 0 && scheduledTime < block.timestamp, "No unstaking notice");

        return _finalizeUnstaking(serviceId, serviceData[serviceId].unstakingNotice[msg.sender].amountsOrIds);

        delete serviceData[serviceId].unstakingNotice[msg.sender];
    }

    function _initiateUnstaking(uint256 serviceId, uint256[] calldata amounts) internal returns (bool finalizeImmediately) {
        uint256[] memory lockerIds = serviceData[serviceId].lockers;
        require(amounts.length == lockerIds.length, "Invalid amounts");

        // NOTE lockers can perform balance checks here and revert if the staker doesn't have enough balance
        for (uint256 i; i < lockerIds.length; ++i) {
            lockerAddresses[lockerIds[i]].onUnstake(msg.sender, serviceId, amounts[i]);
        }

        if (subscriptions[msg.sender].viewCommitment(serviceId) > block.timestamp) {
            // Confirm the unstaking with the Service if the Staker is currently committed
            // The Service can revert.
            finalizeImmediately = serviceData[serviceId].service.onInitializeUnstaking(msg.sender, lockerIds, amounts);
        } else {
            // Let the Staker initiate unstaking if the Staker is no longer committed
            // Notify the Service that the Staker has unstaked.
            // Reverting not allowed.
            try serviceData[serviceId].service.onInitializeUnstaking{gas: SERVICE_UNSTAKE_GAS}(msg.sender, lockerIds, amounts) returns (
                bool finalizeImmediately_
            ) {
                finalizeImmediately = finalizeImmediately_;
            } catch (bytes memory data) {
                emit UnstakingError(serviceId, msg.sender, data);
            }
        }
        return finalizeImmediately;
    }

    function _finalizeUnstaking(uint256 serviceId, uint256[] memory amounts) internal {
        uint256[] memory lockerIds = serviceData[serviceId].lockers;
        require(amounts.length == lockerIds.length, "Invalid amounts");

        // Notify the Service that the Staker is unstaking.
        // Reverting not allowed.
        try serviceData[serviceId].service.onFinalizeUnstaking{gas: SERVICE_UNSTAKE_GAS}(msg.sender) {}
        catch (bytes memory data) {
            emit UnstakingError(serviceId, msg.sender, data);
        }

        // Notify the Lockers that the Staker has unstaked.
        // Reverting not allowed.
        // Note: We assume the Staker trust the Lockers not to revert by causing the call to run out of gas.
        bool stakeIsZero = true;
        for (uint256 i; i < lockerIds.length; ++i) {
            uint256 newStake = lockerAddresses[lockerIds[i]].onUnstake(msg.sender, serviceId, amounts[i]);
            if (newStake != 0) stakeIsZero = false;
        }
        if (stakeIsZero) subscriptions[msg.sender].stopTracking(serviceId);
    }

    function _canUnstakeImmediately(uint256 serviceId, address staker) internal view returns (bool) {
        if (serviceData[serviceId].unstakingNoticePeriod == 0) return true;
        if (slasherUpdates[serviceId].newSlasher != address(0)) return true;
        return false;
    }
}
