// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";
import {ISlasher} from "./interface/ISlasher.sol";
import {LockerBase} from "../template/LockerBase.sol";
import {StakingHub, LockerSettings} from "../StakingHub.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking-Layer.
contract ServicePoS is IService, Ownable {
    StakingHub immutable stakingHub;
    ISlasher immutable slasher;
    LockerBase[] lockerContracts;

    // self-registers as Service, set msg.sender as owner
    constructor(address _stakingHub, LockerSettings[] memory _lockers, LockerBase[] memory _lockerContracts, uint40 unstakingNoticePeriod, address _slasher)
        Ownable(msg.sender)
    {
        stakingHub = StakingHub(_stakingHub);

        stakingHub.registerService(_lockers, unstakingNoticePeriod, _slasher);

        slasher = ISlasher(_slasher);
        lockerContracts = _lockerContracts;
    }

    function initiateSlasherUpdate(address _slasher) public onlyOwner {
        stakingHub.initiateSlasherUpdate(_slasher);
    }

    function finalizeSlasherUpdate() public onlyOwner {
        stakingHub.finalizeSlasherUpdate();
    }

    function freeze(address staker, bytes calldata proof) public onlyOwner {
        slasher.freeze(staker, proof);
    }

    function slash(address staker, uint8[] calldata percentages) public {
        slasher.slash(staker, percentages);
    }

    /// @notice callable by eyeryone, validity checked in Hub
    function kickStaker(address staker, uint256 offendingLockerIndex) public {
        stakingHub.kickOut(staker, offendingLockerIndex);
    }

    // ========== TRIGGERS ==========
    function onSubscribe(address staker) public {
        // i.e. check that staker has sufficient funds in all required lockers
    }
    function onCancelSubscription(address staker) public returns (bool finalizeImmediately) {}
    function onUnsubscribe(address staker) public {}
}
