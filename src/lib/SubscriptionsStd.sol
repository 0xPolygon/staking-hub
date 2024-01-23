// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev The single-linked list data-type for tracking subscriptions.
struct Subscriptions {
    uint256 head;
    mapping(uint256 => SubscriptionsStd.Item) items;
}

// TODO Update docs.
/// @title Subscriptions standard library
/// @notice A library for managing `Subscriptions`.
/// @notice How subscriptions work:
/// @notice - Upon a subscription, there may be a lock-in period required by the Service the Staker is subscribing to.
/// @notice - The subscription remains active until the Staker unsubscribes through the Hub.
/// @dev Do not modify `Subscriptions` manually. Always use `SubscriptionsStd` for reading from and writing to `Subscriptions`.
library SubscriptionsStd {
    // ========== DATA TYPES ==========

    // Review: Is it more gas-efficient to use doubly-linked list? For example, `stopTracking` won't need to iterate over items.
    struct Item {
        bool active;
        uint256 lockedInUntil;
        uint256 lastFreezeEnd;
        uint256 next;
    }

    // ========== ACTIONS ==========

    /// @notice Starts tracking a new subscription, or updates the lock-in period of the subscription that is already being tracked.
    function track(Subscriptions storage list, uint256 service, uint256 lockInUntil) public {
        assert(service != 0);

        // Track a new subscription.
        if (!isActive(list, service)) {
            list.items[service] = Item(true, lockInUntil, 0, list.head);
            list.head = service;
        } else {
            // Update the lock-in period.
            list.items[service].lockedInUntil = lockInUntil;
        }
    }

    /// @notice Stops tracking a subscription.
    function stopTracking(Subscriptions storage list, uint256 service) public {
        assert(isActive(list, service));

        if (list.head == service) {
            list.head = list.items[list.head].next;
            delete list.items[service];
            return;
        }

        uint256 current = list.head;
        while (list.items[current].next != 0) {
            if (list.items[current].next == service) {
                list.items[current].next = list.items[list.items[current].next].next;
                delete list.items[service];
                return;
            }
            current = list.items[current].next;
        }
    }

    /// @notice Sets the end of the freeze period of a subscription that is already being tracked.
    function freeze(Subscriptions storage list, uint256 service, uint256 newFreezeEnd) public {
        assert(isActive(list, service));
        assert(newFreezeEnd > list.items[service].lastFreezeEnd);

        list.items[service].lastFreezeEnd = newFreezeEnd;
    }

    /// @notice Resets the end of the freeze period of a subscription that is already being tracked.
    function unfreeze(Subscriptions storage list, uint256 service) public {
        assert(isActive(list, service));

        list.items[service].lastFreezeEnd = 0;
    }

    // ========== QUERIES ==========

    /// @return Whether a subscription is active.
    function isActive(Subscriptions storage list, uint256 service) public view returns (bool) {
        return list.items[service].active;
    }

    // Review: Is `isActive` check needed?
    /// @return Whether a subscription is active.
    function isLockedIn(Subscriptions storage list, uint256 service) public view returns (bool) {
        return block.timestamp < list.items[service].lockedInUntil;
    }

    /// @return Whether the Staker is frozen.
    function isFrozen(Subscriptions storage list, uint256 service) public view returns (bool) {
        return block.timestamp < list.items[service].lastFreezeEnd;
    }

    // TODO: Remove this function if not needed.
    function getUnlock(Subscriptions storage list, uint256 service) public view returns (uint256) {
        assert(isActive(list, service));

        return list.items[service].lockedInUntil;
    }

    // ========== UTILITIES ==========

    /// @dev Use to get the next subscription from the linked list.
    function iterate(Subscriptions storage list, uint256 service) public view returns (uint256) {
        assert(isActive(list, service));

        return list.items[service].next;
    }
}
