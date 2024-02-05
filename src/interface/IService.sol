// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

// TODO Update docs.
/// @title IService
/// @author Polygon Labs
/// @notice A Service represents a network.
/// @notice Stakers can subscribe to the Service by restaking.
interface IService {
    // ========== TRIGGERS ==========

    /// @notice Lets a Staker restake in the Service.
    /// @notice Performs all neccessary checks on the Staker (e.g., voting power, whitelist, BLS-key, etc.).
    /// @dev Called by the Hub when a Staker subscribes to the Service.
    /// @dev The Service can revert.
    function onRestake(address staker, uint256[] calldata strategies, uint256[] calldata amountsOrIds, uint256 committingUntil) external;

    /// @notice Lets a Staker unstake from the Service.
    /// @notice Performs all neccessary checks on the Staker.
    /// @notice A Service that requires unstaking notice may still choose allow the Staker to finalize the unstaking immediately.
    /// @dev Called by the Hub when a Staker unsubscribes from the Service.
    /// @dev The Service can revert when the subscription hasn't expired.
    function onInitializeUnstaking(address staker, uint256[] calldata strategyIds, uint256[] calldata amountsOrIds)
        external
        returns (bool finalizeImmediately);
    function onFinalizeUnstaking(address staker) external;

    /// @notice Functionality not defined.
    /// @dev Called by the Hub when a Staker has been frozen by a Slasher of the Service.
    function onFreeze(address staker) external;
}
