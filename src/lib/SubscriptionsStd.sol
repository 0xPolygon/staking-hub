// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// TODO Ditch the list and change to deterministic tracking with a counter.

/// @dev The single-linked list data-type for tracking subscriptions.
struct Subscriptions {
    uint256 head;
    mapping(uint256 service => SubscriptionsStd.Details details) items;
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

    struct Details {
        bool exists;
        uint256 committedUntil;
        uint256 lastFreezingEnd;
        uint256 next;
    }

    // ========== ACTIONS ==========

    /// @notice Starts tracking a new subscription, or updates the lock-in period of the subscription that is already being tracked.
    function track(Subscriptions storage self, uint256 service, uint256 commitUntil) public {
        assert(service != 0);

        // Track a new subscription.
        if (!exists(self, service)) {
            self.items[service] = Details(true, commitUntil, 0, self.head);
            self.head = service;
        } else {
            // Update the lock-in period.
            self.items[service].committedUntil = commitUntil;
        }
    }

    /// @notice Stops tracking a subscription.
    function stopTracking(Subscriptions storage self, uint256 service) public {
        assert(exists(self, service));

        if (self.head == service) {
            self.head = self.items[self.head].next;
            delete self.items[service];
            return;
        }

        uint256 current = self.head;
        while (self.items[current].next != 0) {
            if (self.items[current].next == service) {
                self.items[current].next = self.items[self.items[current].next].next;
                delete self.items[service];
                return;
            }
            current = self.items[current].next;
        }
    }

    /// @notice Sets the end of the freeze period of a subscription that is already being tracked.
    function freeze(Subscriptions storage self, uint256 service, uint256 newFreezeEnd) public {
        assert(exists(self, service));
        assert(newFreezeEnd > self.items[service].lastFreezingEnd);

        self.items[service].lastFreezingEnd = newFreezeEnd;
    }

    /// @notice Resets the end of the freeze period of a subscription that is already being tracked.
    function unfreeze(Subscriptions storage self, uint256 service) public {
        assert(exists(self, service));

        self.items[service].lastFreezingEnd = 0;
    }

    // ========== QUERIES ==========

    function hasSubscriptions(Subscriptions storage self) public view returns (bool) {
        return self.head != 0;
    }

    /// @return Whether a subscription is active.
    function exists(Subscriptions storage self, uint256 service) public view returns (bool) {
        return self.items[service].exists;
    }

    /// @return Whether a subscription is active.
    function isCommitted(Subscriptions storage self, uint256 service) public view returns (bool) {
        assert(exists(self, service));

        return block.timestamp < self.items[service].committedUntil;
    }

    /// @return Whether the Staker is frozen.
    function isFrozen(Subscriptions storage self) public view returns (bool) {
        uint256 currentServiceId = self.head;
        while (currentServiceId != 0) {
            if (block.timestamp < self.items[currentServiceId].lastFreezingEnd) return true;
            currentServiceId = iterate(self, currentServiceId);
        }

        return false;
    }

    function viewCommitment(Subscriptions storage self, uint256 service) public view returns (uint256) {
        assert(exists(self, service));

        return self.items[service].committedUntil;
    }

    // ========== UTILITIES ==========

    /// @dev Use to get the next subscription from the linked list.
    function iterate(Subscriptions storage self, uint256 service) public view returns (uint256) {
        assert(exists(self, service));

        return self.items[service].next;
    }
}
