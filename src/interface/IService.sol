// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Service
 * @author Polygon Labs
 * @notice
 * Please see PRC-X for more details.
 */
interface IService {
    /**
     * Processes subscription request. Should perform all necessary checks.
     * @dev
     * Triggered by hub.
     */
    function onSubscribe(address staker, uint256 lockingInUntil) external;

    /**
     * Processes unsubscription request. Should perform all necessary checks.
     * @dev
     * Triggered by hub.
     * Cannot revert is staker is not locked-in, but may forward warning data. Gas is limited if staker is not locked-in.
     */
    function onInitiateUnsubscribe(address staker) external;

    /**
     * Processes unsubscription.
     * @dev
     * Triggered by hub.
     * Cannot revert. Gas is limited.
     */
    function onFinalizeUnsubscribe(address staker) external;
}
