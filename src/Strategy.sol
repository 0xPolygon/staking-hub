// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

abstract contract Strategy {
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
