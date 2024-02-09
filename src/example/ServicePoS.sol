// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";
import {StakingLayer, SlashingInput} from "../StakingLayer.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking-Layer.
contract ServicePoS is IService, Ownable {
    StakingLayer immutable stakingLayer;

    // self-registers as Service, set msg.sender as owner
    constructor(address _stakingLayer, SlashingInput[] memory _lockers, uint40 unstakingNoticePeriod, address slasher) Ownable(msg.sender) {
        stakingLayer = StakingLayer(_stakingLayer);
        stakingLayer.registerService(_lockers, unstakingNoticePeriod, slasher);
    }

    function initiateSlasherUpdate(address _slasher) public onlyOwner {
        stakingLayer.initiateSlasherUpdate(_slasher);
    }

    function finalizeSlasherUpdate() public onlyOwner {
        stakingLayer.finalizeSlasherUpdate();
    }

    // ========== TRIGGERS ==========
    function onCancelSubscription(address staker) public returns (bool finalizeImmediately) {}
    function onUnsubscribe(address staker) public {}

    function onFreeze(address staker) public {}
}
