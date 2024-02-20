// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";
import {ISlasher} from "./interface/ISlasher.sol";
import {ERC20Locker} from "../template/ERC20Locker.sol";
import {StakingHub, LockerSettings} from "../StakingHub.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking-Layer.
contract ServicePoS is IService, Ownable {
    StakingHub immutable stakingHub;
    ISlasher immutable slasher;
    ERC20Locker[] lockerContracts;

    // self-registers as Service, set msg.sender as owner
    constructor(address _stakingHub, LockerSettings[] memory _lockers, ERC20Locker[] memory _lockerContracts, uint40 unsubNotice, address _slasher)
        Ownable(msg.sender)
    {
        stakingHub = StakingHub(_stakingHub);

        stakingHub.registerService(_lockers, unsubNotice, _slasher);

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

    /// @notice services monitor
    function terminateStaker(address staker) public onlyOwner {
        stakingHub.terminate(staker);
    }

    // ========== TRIGGERS ==========
    function onSubscribe(address staker, uint256 lockingInUntil) public {
        // i.e. check that staker has sufficient funds in all required lockers
    }

    function onInitiateUnsubscribe(address staker) public {}

    function onFinalizeUnsubscribe(address staker) public {}
}
