// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {LockerManager} from "./LockerManager.sol";

struct Staker {
    uint216 subscriptionCount;
    // TODO invariant test that frozenUntil is always >= any subscription.frozenUntil
    uint40 frozenUntil;
    uint40 freezeCount;
}

struct Subscription {
    bool subscribed;
    uint40 commitUntil;
    uint40 unstakeScheduledFor;
    uint40 frozenUntil;
}

abstract contract StakerManager is LockerManager {
    struct StakerStorage {
        mapping(address staker => Staker) data;
        mapping(address staker => mapping(uint256 service => Subscription)) subscriptions;
    }

    StakerStorage internal _stakers;

    function _restake(address staker, uint256 service, uint40 commitUntil) internal {
        require(commitUntil > block.timestamp, "Invalid commit time");
        Subscription storage sub = _stakers.subscriptions[staker][service];
        require(!sub.subscribed, "Already subscribed");
        _stakers.subscriptions[staker][service] = Subscription(true, commitUntil, 0, 0);
        ++_stakers.data[staker].subscriptionCount;
        emit Restaked(staker, service, commitUntil);
    }

    function _initiateUnstaking(address staker, uint256 service) internal {
        Subscription storage sub = _stakers.subscriptions[staker][service];
        require(sub.subscribed, "Not subscribed");
        require(sub.unstakeScheduledFor == 0, "Unstake already scheduled");
        sub.unstakeScheduledFor = uint40(block.timestamp + _unstakingNotice(service));
        emit UnstakingInitiated(staker, service);
    }

    function _finaliseUnstaking(address staker, uint256 service) internal {
        Subscription storage sub = _stakers.subscriptions[staker][service];
        require(sub.subscribed, "Not subscribed");
        uint256 unscheduledFor = sub.unstakeScheduledFor;
        require(unscheduledFor != 0, "Unstake not scheduled");
        require(block.timestamp > unscheduledFor, "Unstake not due");
        sub.subscribed = false;
        sub.unstakeScheduledFor = 0;
        --_stakers.data[staker].subscriptionCount;
        emit Unstaked(staker, service);
    }

    function _isCommittedTo(address staker, uint256 service) internal view virtual returns (bool) {
        return _stakers.subscriptions[staker][service].commitUntil > block.timestamp;
    }

    function _unstakingNotice(uint256 service) internal view virtual returns (uint40 notice);
}
