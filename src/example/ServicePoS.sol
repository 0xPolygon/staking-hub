// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";
import {StakingHub, SlashingInput} from "../StakingHub.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking-Layer.
contract ServicePoS is IService, Ownable {
    StakingHub immutable stakingHub;

    // self-registers as Service, set msg.sender as owner
    constructor(address _stakingHub, SlashingInput[] memory _lockers, uint40 unstakingNoticePeriod, address slasher) Ownable(msg.sender) {
        stakingHub = StakingHub(_stakingHub);
        stakingHub.registerService(_lockers, unstakingNoticePeriod, slasher);
    }

    function initiateSlasherUpdate(address _slasher) public onlyOwner {
        stakingHub.initiateSlasherUpdate(_slasher);
    }

    function finalizeSlasherUpdate() public onlyOwner {
        stakingHub.finalizeSlasherUpdate();
    }

    // ========== TRIGGERS ==========
    function onCancelSubscription(address staker) public returns (bool finalizeImmediately) {}
    function onUnsubscribe(address staker) public {}

    function onFreeze(address staker) public {}
}
