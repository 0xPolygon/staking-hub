// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Service
/// @author Polygon Labs
interface IService {
    function onSubscribe(address staker) external;

    function onInitiateUnsubscribe(address staker) external;

    function onFinalizeUnsubscribe(address staker) external;
}
