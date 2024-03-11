// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {IService} from "../interface/IService.sol";
import {Slasher} from "../example/Slasher.sol";
import {ERC20Locker} from "../template/ERC20Locker.sol";
import {StakingHub, LockerSettings} from "../StakingHub.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ServicePoS
/// @author Polygon Labs
/// @notice Represents the Polygon PoS network
/// @notice Stakers can subscribe to this Service using the Staking Hub.
contract ServicePoS is IService, Ownable {
    StakingHub immutable stakingHub;
    Slasher public slasher;
    ERC20Locker[] public lockerContracts;

    uint256 public id;

    // self-registers as Service, set msg.sender as owner
    constructor(address _stakingHub, ERC20Locker[] memory _lockerContracts) Ownable(msg.sender) {
        stakingHub = StakingHub(_stakingHub);

        lockerContracts = _lockerContracts;
    }

    function init(LockerSettings[] memory _settings, uint40 unsubNotice) public {
        slasher = new Slasher(stakingHub);

        id = stakingHub.registerService(_settings, unsubNotice, address(slasher));
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

    function onInitiateUnsubscribe(address staker, bool) public {}

    function onFinalizeUnsubscribe(address staker) public {}
}
