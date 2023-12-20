// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {SubscriptionTracker} from "src/lib/SubscriptionTracker.sol";

/// @title Strategy
/// @author Polygon Labs
/// @notice A Strategy holds and manages Stakers' funds.
/// @notice A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.
abstract contract Strategy is SubscriptionTracker {
    // TODO Allow POL, ERC20s, NFTs.
    mapping(address staker => uint256 balance) private _balances;

    /// @return The amount of funds the Staker has in the Strategy.
    function balanceOf(address staker) public view returns (uint256) {
        return _balances[staker];
    }

    /// @notice Adds funds to be available to a Staker for restaking.
    /// @dev Called by the Staker.
    function deposit() external payable {
        _balances[msg.sender] += msg.value;
    }

    /// @notice Retrieves all Staker's funds from the Strategy.
    /// @notice The Staker must be unsubscribed from all Services first.
    /// @notice A Staker is unsubscribed from a Service if the Staker unsubscribed via the Hub, or the subscription has expired.
    /// @dev Called by the Staker.
    function withdraw() external {
        Subscriptions storage $ = subscriptions[msg.sender];

        require($.tail != 0 && block.timestamp >= $.tail || $.head == 0 && $.tail == 0, "Cannot withdraw because there are active subscriptions");

        uint256 value = _balances[msg.sender];
        _balances[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: value}("");
        require(success, "Withdrawal failed");
    }

    /// @notice Stats tracking a subscription.
    /// @dev Called by the Hub when a Staker has subscribed to a Services that uses the Strategy.
    function onSubscribe(address staker, uint256 service, uint256 until) external {
        addSubscription(staker, until, service);
    }

    /// @notice Stops tracking a subscription.
    /// @dev Called by the Hub when a Staker has unsubscribed from a Services that uses the Strategy.
    function onUnsubscribe(address staker, uint256 service) external {
        Subscriptions storage $ = subscriptions[staker];
        removeSubscription(staker, $._lastUntil[service], service);
    }

    /// @notice Takes a portion of a Staker's funds away.
    /// @dev Called by the Hub when a Staker has subscribed to a Services that uses the Strategy.
    function onSlash(address staker, uint8 percentage) external virtual {
        uint256 amount = _balances[staker] * percentage;

        _balances[staker] -= amount;

        // TODO What to do with the slashed funds?
        // Burn the slashed amount.
        (bool success,) = address(0).call{value: amount}("");
        require(success, "Slash failed");
    }

    // Note:
    // The current implementation uses internal subscription tracking.
    //
    // An alternative approach is to record each Service the Staker subscribes to,
    // and check if all subscriptions have expired via the Hub on withdraw.
    // Similar approach can be imolemented internally as well.
}
