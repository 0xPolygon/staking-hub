// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

/// @title Service
/// @author Polygon Labs
/// @notice A service is the source of truth for a network.
/// @dev Service base interface.
abstract contract Service {
    /// @return The maximum slash percentage.
    function slashPercentage() external view virtual returns (uint8);

    /// @notice Performs all checks on e.g., sufficient voting power, whitelist, bls key check, etc.
    /// @dev Permissioned API endpoint.
    /// @dev Called by the Hub.
    /// @dev Should revert if the Staker did not pass the check.
    function onSubscribe(address staker, uint256 stakedUntil) external {
        _validateSubscription(staker, stakedUntil);
    }

    function _validateSubscription(address staker, uint256 stakedUntil) internal virtual;
    /* For example:
        // Single strategy
        REQUIRE STR.BALANCEOF > 0
        // multiple strategies required
        REQUIRE STR1.BALANCEOF > 0 && ...
        // subset of strategies
        REQUIRE STR1.BALANCEOF > 0 || ... */

    /// @notice Validates an unsubscription from the service
    /// @dev Permissioned API endpoint.
    /// @dev Called by the Hub.
    function onUnsubscribe(address staker) external {
        _validateUnsubscription(staker);
    }

    /// @dev Should revert if the Staker did not pass the check.
    function _validateUnsubscription(address validator) internal virtual;
}
