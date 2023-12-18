// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import "forge-std/console.sol";

abstract contract Strategy {
    // ====== Start of AI generated code ====== //
    // 🧑‍💻 Modified by a human
    // 🛑 Not audited
    // 🚧 Work in progress

    struct Until {
        uint256 timestamp;
        mapping(uint256 => bool) services;
        uint256 servicesCounter;
        uint256 next;
        uint256 prev;
    }

    //struct Subscriptions {
    mapping(uint256 timestampAsId => Until) list; // Doubly linked list
    uint256 head;
    uint256 tail;
    // For subscription extension functionality
    mapping(uint256 service => uint256 untilId) _currentUntil;
    //}

    //mapping(address staker => Subscriptions) subscriptions;

    // Function to create a new Until
    function _createUntil(uint256 _timestamp) private {
        uint256 current = head;
        uint256 newId = _timestamp; // Unique ID for the new Until

        // Check if the list is empty or the new Until is the earliest
        if (current == 0 || list[current].timestamp > _timestamp) {
            Until storage newUntil = list[newId];
            newUntil.timestamp = _timestamp;
            newUntil.next = current; // If list is empty, newUntil.next is 0; otherwise, it's the old head
            newUntil.prev = 0; // The new node is now the head, so its prev is 0

            if (current != 0) {
                list[current].prev = newId; // Update the old head's prev to point to the new head
            }

            head = newId; // Update the head to the new node

            if (tail == 0) {
                tail = newId; // If the list was empty, the new node is also the tail
            }

            return;
        }

        // Find the correct position to insert the new Until
        while (list[current].next != 0 && list[list[current].next].timestamp < _timestamp) {
            current = list[current].next;
        }

        Until storage newUntil = list[newId];
        newUntil.timestamp = _timestamp;
        newUntil.next = list[current].next;
        newUntil.prev = current;

        list[current].next = newId;

        if (newUntil.next == 0) {
            tail = newId; // If the new node is at the end, update the tail
        } else {
            list[newUntil.next].prev = newId; // Otherwise, update the next node's prev
        }
    }

    // Function to add a service; can create a new Until, remove a Service, remove an Until
    function addService(uint256 _timestamp, uint256 _service) internal {
        uint256 _untilId = _timestamp; // Unique ID for the new Until

        require(_untilId != 0, "Invalid timestamp");

        // If subscription exists, require that the new timestamp is greater than the current one
        if (_currentUntil[_service] != 0) {
            require(_timestamp > list[_currentUntil[_service]].timestamp, "Timestamp must be greater than the current one");
            // Remove service from the old Until
            removeService(_currentUntil[_service], _service);
        }

        Until storage until = list[_untilId];

        // If Until does not exist, create it
        if (until.timestamp == 0) {
            _createUntil(_timestamp);
        }

        if (!until.services[_service]) {
            until.services[_service] = true;
            ++until.servicesCounter;
        }

        // Update service tracker
        _currentUntil[_service] = _untilId;
    }

    // Function to remove a service for an existing Until; can remove an Until
    function removeService(uint256 _untilId, uint256 _service) internal {
        require(_untilId != 0, "Invalid Until");
        Until storage until = list[_untilId];
        require(until.timestamp != 0, "Until does not exist");
        require(until.services[_service], "Service does not exist");

        until.services[_service] = false;
        --until.servicesCounter;

        // If Until has no more services, remove it
        if (until.servicesCounter == 0) {
            _deleteUntil(_untilId);
        }

        // Update service tracker
        _currentUntil[_service] = 0;
    }

    // Function to remove an Until; requires that all services have been removed
    function _deleteUntil(uint256 _untilId) private {
        require(_untilId != 0, "Cannot remove sentinel Until");

        Until storage untilToRemove = list[_untilId];

        // Check if Until exists in the list
        require(untilToRemove.timestamp != 0, "Until does not exist");

        // Check if unsubscribed from all services
        require(untilToRemove.servicesCounter == 0, "Cannot remove Until with active services");

        uint256 prevUntil = untilToRemove.prev;
        uint256 nextUntil = untilToRemove.next;

        // Adjust pointers of adjacent Untils
        if (prevUntil != 0) {
            list[prevUntil].next = nextUntil;
        } else {
            head = nextUntil; // Update head if removing the first Until
        }

        if (nextUntil != 0) {
            list[nextUntil].prev = prevUntil;
        } else {
            tail = prevUntil; // Update tail if removing the last Until
        }

        // Delete the Until from the mapping
        delete list[_untilId];
    }

    // ====== End of AI generated code ====== //

    address private constant HUB = address(0);

    // TODO Can be POL, ERC20s, NFTs.
    mapping(address staker => uint256 balance) private _balances;

    // The following variables are used for locking funds.
    // _lockedUntil will be set to the highest until value.
    // Problem: If the Staker unsubscribes from all _lockers (the ones with the highest until value), the funds will become unlocked.
    // How to implement the solution without poluting the state?
    mapping(address staker => uint256 unlockTime) private _lockedUntil;
    mapping(address staker => uint256[] lockers) private _lockers;
    mapping(address staker => uint256 lockersCounter) private _lockersCounter;

    /// @notice Adds funds to be available for restaking.
    /// @dev Called by a Staker.
    function deposit() external payable {
        _balances[msg.sender] += msg.value;
    }

    /// @return The amount of funds the Staker has in the Strategy.
    function balanceOf(address staker) external view returns (uint256) {
        return _balances[staker];
    }

    /// @dev Called buy the Hub when a Staker subscribes.
    function onSubscribe(address staker, uint256 service, uint256 until) external {
        _lock(staker, service, until);
    }

    /// @notice Updates an unlock time.
    function _lock(address staker, uint256 service, uint256 until) internal {
        if (_lockedUntil[staker] < until) {
            return;
        } else if (_lockedUntil[staker] == until) {
            _lockers[staker].push(service);
        } else {
            delete _lockers[staker];
            delete _lockersCounter[staker];
            _lockers[staker].push(service);
            _lockedUntil[staker] = until;
        }
        ++_lockersCounter[staker];
    }

    /// @notice Withdraws funds from the Strategy.
    /// @dev Called by a Staker.
    function withdraw() external {
        // lock withdrawal until unlockTime
        require(_lockedUntil[msg.sender] < block.timestamp, "Locked");
        // or the Hub has notified that the Staker has unsubscribed
        require(_lockersCounter[msg.sender] == 0, "Locked");

        (bool success,) = msg.sender.call{value: _balances[msg.sender]}("");
        require(success, "Failed");
    }

    /// @notice Notifies the Strategy that the Staker has unsubscribed from a Service.
    /// @dev Called by the Hub.
    function onUnsubscribe(address staker, uint256 service) external {
        for (uint256 i; i < _lockers[staker].length; ++i) {
            if (_lockers[staker][i] == service) {
                delete _lockers[staker][i];
                --_lockersCounter[staker];
                break;
            }
        }
    }

    /// @dev Called by the Hub.
    function onFreeze(address staker) external {
        require(msg.sender == HUB, "Unauthorized");
        _onFreeze(staker);
    }

    function _onFreeze(address staker) internal virtual;
    // e.g. may want to freeze withdrawals
}
