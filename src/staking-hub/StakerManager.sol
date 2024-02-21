// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {LockerManager} from "./LockerManager.sol";

/*struct Staker {
    uint216 subscriptionCount;
}*/

struct Subscription {
    bool subscribed;
    uint40 lockedInUntil;
    uint40 unsubscribableFrom;
    uint40 frozenUntil;
}

abstract contract StakerManager is LockerManager {
    struct StakerStorage {
        //mapping(address staker => Staker) data;
        mapping(address staker => mapping(uint256 service => Subscription)) subscriptions;
    }

    StakerStorage internal _stakers;

    function _subscribe(address staker, uint256 service, uint40 lockedInUntil) internal {
        Subscription storage sub = _stakers.subscriptions[staker][service];
        require(!sub.subscribed, "Already subscribed");
        require(lockedInUntil > block.timestamp, "Invalid subscription term");
        _stakers.subscriptions[staker][service] = Subscription(true, lockedInUntil, 0, 0);
        //++_stakers.data[staker].subscriptionCount;
        emit Subscribed(staker, service, lockedInUntil);
    }

    function _initiateUnsubscription(address staker, uint256 service) internal returns (uint40 unsubscribableFrom) {
        Subscription storage sub = _stakers.subscriptions[staker][service];
        require(sub.subscribed, "Not subscribed");
        require(sub.unsubscribableFrom == 0, "Unsubscription already initiated");
        unsubscribableFrom = uint40(block.timestamp + _unsubNotice(service));
        sub.unsubscribableFrom = unsubscribableFrom;
        emit UnsubscriptionInitiated(staker, service);
    }

    function _unsubscribe(address staker, uint256 service, bool force) internal {
        Subscription storage sub = _stakers.subscriptions[staker][service];
        require(sub.subscribed, "Not subscribed");
        if (!force) {
            require(sub.unsubscribableFrom != 0, "Unsubscription not initiated");
            require(block.timestamp > sub.unsubscribableFrom, "Cannot finalize unsubscription yet");
        }
        sub.subscribed = false;
        sub.unsubscribableFrom = 0;
        //--_stakers.data[staker].subscriptionCount;
        emit Unsubscribed(staker, service);
    }

    function _isLockedIn(address staker, uint256 service) internal view virtual returns (bool) {
        return _stakers.subscriptions[staker][service].lockedInUntil > block.timestamp;
    }

    function _unsubNotice(uint256 service) internal view virtual returns (uint40 notice);
}
