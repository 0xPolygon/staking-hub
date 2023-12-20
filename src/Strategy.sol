// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SubscriptionTracker} from "src/lib/SubscriptionTracker.sol";

// Note:
// This is internal subscription tracking.
//
// An alternative is to record each service the user subscribes to
// and then check if all the subscriptions have expired
// via the Hub (subscribedToService) on withdraw.

abstract contract Strategy is SubscriptionTracker {
    address private constant HUB = address(0);

    // TODO Can be POL, ERC20s, NFTs.
    mapping(address staker => uint256 balance) private _balances;

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
        addSubscription(staker, until, service);
    }

    /// @notice Withdraws funds from the Strategy.
    /// @notice Funds are locked until no active subscription remain (expired or unsubbed from).
    /// @dev Called by a Staker.
    function withdraw() external {
        Subscriptions storage $ = subscriptions[msg.sender];

        require($.tail != 0 && block.timestamp >= $.tail || $.head == 0 && $.tail == 0, "Funds locked");

        uint256 value = _balances[msg.sender];
        _balances[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: value}("");
        require(success, "Withdrawal failed");
    }

    /// @notice Notifies the Strategy that the Staker has unsubscribed from a Service.
    /// @dev Called by the Hub.
    function onUnsubscribe(address staker, uint256 service) external {
        Subscriptions storage $ = subscriptions[staker];
        removeSubscription(staker, $._lastUntil[service], service);
    }

    //function onFreeze(address staker) external virtual {}

    function onSlash(address staker, uint8 percentage) external virtual {
        uint256 amount = _balances[staker] * percentage;
        _balances[staker] -= amount;

        // Burn, for now.
        (bool success,) = address(0).call{value: amount}("");
        require(success, "Slash failed");
    }
}
