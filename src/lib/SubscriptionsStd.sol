// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev The single-linked list data-type for tracking subscriptions.
struct Subscriptions {
    uint256 counter;
    uint256 freezingCounter;
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
    }

    // ========== ACTIONS ==========

    /// @notice Starts tracking a new subscription, or updates the lock-in period of the subscription that is already being tracked.
    function track(Subscriptions storage self, uint256 service, uint256 commitUntil) public {
        assert(service != 0);

        // Track a new subscription.
        if (!exists(self, service)) {
            self.items[service] = Details(true, commitUntil, 0);
            self.counter++;
        } else {
            // Update the lock-in period.
            self.items[service].committedUntil = commitUntil;
        }
    }

    /// @notice Stops tracking a subscription.
    function stopTracking(Subscriptions storage self, uint256 service) public {
        assert(exists(self, service));
        delete self.items[service];
        self.counter--;
    }

    /// @notice Sets the end of the freezing period of a subscription that is already being tracked.
    function freeze(Subscriptions storage self, uint256 service, uint256 newFreezeEnd) public {
        assert(exists(self, service));
        assert(newFreezeEnd > self.items[service].lastFreezingEnd);
        self.freezingCounter++;
        self.items[service].lastFreezingEnd = newFreezeEnd;
    }

    /// @notice Resets the end of the freeze period of a subscription that is already being tracked.
    function unfreeze(Subscriptions storage self, uint256 service) public {
        assert(exists(self, service));
        self.freezingCounter--;
        self.items[service].lastFreezingEnd = 0;
    }

    // ========== QUERIES ==========

    function hasSubscriptions(Subscriptions storage self) public view returns (bool) {
        return self.counter != 0;
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
        self.freezingCounter != 0;
    }

    function viewCommitment(Subscriptions storage self, uint256 service) public view returns (uint256) {
        assert(exists(self, service));

        return self.items[service].committedUntil;
    }
}
