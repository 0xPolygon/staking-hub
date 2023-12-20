// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

abstract contract SubscriptionTracker {
    // ====== Start of AI generated code ====== //
    // 💬 Linked list
    // 🧑‍💻 Modified by a human
    // ❗️ Not audited

    struct Until {
        uint256 timestamp;
        mapping(uint256 => bool) services;
        uint256 servicesCounter;
        uint256 next;
        uint256 prev;
    }

    struct Subscriptions {
        mapping(uint256 timestampAsId => Until) list;
        uint256 head;
        uint256 tail;
        // For subscription extension functionality (can also be used to check if the user has an active subscription with a service)
        mapping(uint256 service => uint256 untilId) _lastUntil;
    }

    mapping(address staker => Subscriptions) subscriptions;

    // Function to add a service; can create a new Until, remove a Service, remove an Until
    function addSubscription(address _staker, uint256 _timestamp, uint256 _service) internal {
        Subscriptions storage $ = subscriptions[_staker];

        require(_timestamp != 0, "Invalid timestamp");
        require(_timestamp > block.timestamp, "Invalid timestamp");

        uint256 _untilId = _timestamp; // Unique ID for the new Until

        // If subscription exists, require that the new timestamp is greater than the current one
        if ($._lastUntil[_service] > block.timestamp) {
            require(_timestamp > $.list[$._lastUntil[_service]].timestamp, "Timestamp must be greater than the current one");
            // Remove service from the old Until
            removeSubscription(_staker, $._lastUntil[_service], _service);
        }

        Until storage until = $.list[_untilId];

        // If Until does not exist, create it
        if (until.timestamp == 0) {
            _createUntil($, _timestamp);
        }

        if (!until.services[_service]) {
            until.services[_service] = true;
            ++until.servicesCounter;
        }

        // Update service tracker
        $._lastUntil[_service] = _untilId;
    }

    // Function to remove a service for an existing Until; can remove an Until
    function removeSubscription(address _staker, uint256 _untilId, uint256 _service) internal {
        Subscriptions storage $ = subscriptions[_staker];

        require(_untilId != 0, "Invalid Until");
        Until storage until = $.list[_untilId];
        require(until.timestamp != 0, "Until does not exist");
        require(until.services[_service], "Service does not exist");

        until.services[_service] = false;
        --until.servicesCounter;

        // If Until has no more services, remove it
        if (until.servicesCounter == 0) {
            _deleteUntil($, _untilId);
        }
    }

    // Function to create a new Until
    function _createUntil(Subscriptions storage $, uint256 _timestamp) private gasSaving($) {
        uint256 current = $.tail;
        uint256 newId = _timestamp; // Unique ID for the new Until

        // Check if the list is empty or the new Until is the latest
        if (current == 0 || $.list[current].timestamp < _timestamp) {
            Until storage newUntil = $.list[newId];
            newUntil.timestamp = _timestamp;
            newUntil.prev = current; // If list is empty, newUntil.prev is 0; otherwise, it's the old tail
            newUntil.next = 0; // The new node is now the tail, so its next is 0

            if (current != 0) {
                $.list[current].next = newId; // Update the old tail's next to point to the new tail
            }

            $.tail = newId; // Update the tail to the new node

            if ($.head == 0) {
                $.head = newId; // If the list was empty, the new node is also the head
            }

            return;
        }

        // Traverse backwards to find the correct position to insert the new Until
        while ($.list[current].prev != 0 && $.list[$.list[current].prev].timestamp > _timestamp) {
            current = $.list[current].prev;
        }

        Until storage newUntil = $.list[newId];
        newUntil.timestamp = _timestamp;
        newUntil.prev = $.list[current].prev;
        newUntil.next = current;

        if (newUntil.prev != 0) {
            $.list[newUntil.prev].next = newId;
        } else {
            $.head = newId; // Update the head if the new node is now the first node
        }

        $.list[current].prev = newId;
    }

    // Function to remove an Until; requires that all services have been removed or the Until has expired
    function _deleteUntil(Subscriptions storage $, uint256 _untilId) private {
        require(_untilId != 0, "Cannot remove sentinel Until");

        Until storage untilToRemove = $.list[_untilId];

        // Check if Until exists in the list
        require(untilToRemove.timestamp != 0, "Until does not exist");

        // Check if unsubscribed from all services
        require(untilToRemove.servicesCounter == 0 || block.timestamp >= untilToRemove.timestamp, "Cannot remove Until with active services");

        uint256 prevUntil = untilToRemove.prev;
        uint256 nextUntil = untilToRemove.next;

        // Adjust pointers of adjacent Untils
        if (prevUntil != 0) {
            $.list[prevUntil].next = nextUntil;
        } else {
            $.head = nextUntil; // Update head if removing the first Until
        }

        if (nextUntil != 0) {
            $.list[nextUntil].prev = prevUntil;
        } else {
            $.tail = prevUntil; // Update tail if removing the last Until
        }

        // Delete the Until from the mapping
        delete $.list[_untilId];
    }

    // ====== End of AI generated code ====== //

    /// @dev Tries to save gas and clean state by deleting the first 'until'.
    /// @dev Use with _createUntil.
    /// @dev Saves on gas as long as subscriptions expire faster than new ones are created, and Services do not unsubscribe Stakers before 'until'.
    /// @dev Saves ~300 G/Tx. Trying costs ~170 G.
    modifier gasSaving(Subscriptions storage $) {
        if ($.head != 0 && block.timestamp >= $.head) {
            uint256 headId = $.head;
            uint256 nextUntil = $.list[$.head].next;

            if (nextUntil != 0) {
                $.list[nextUntil].prev = 0;
            } else {
                $.tail = 0;
            }

            $.head = nextUntil;

            delete $.list[headId];
        }
        _;
    }
}
