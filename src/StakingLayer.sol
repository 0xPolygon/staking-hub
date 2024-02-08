// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {SlashingManager} from "./staking-layer/SlashingManager.sol";
import {SlashingInput} from "./interface/IStakingLayer.sol";
import {PackedUints} from "./lib/PackedUints.sol";

// import {ServiceManager, ServiceStorage, SlashingInput} from "./lib/ServiceManager.sol";

contract StakingLayer is SlashingManager {
    using PackedUints for uint256;

    function registerLocker() external returns (uint256 id) {
        return _setLocker(msg.sender);
    }

    function registerService(SlashingInput[] calldata lockers, uint40 unstakingNoticePeriod, address slasher) external returns (uint256 id) {
        (uint256[] memory lockerIds, uint256 slashingPercentages) = _formatLockers(lockers);
        id = _setService(msg.sender, lockerIds, slashingPercentages, unstakingNoticePeriod);
        _setSlasher(id, slasher);
    }

    function restake(uint256 service, uint40 commitUntil) external notFrozen {
        _restake(msg.sender, service, commitUntil);
        uint256[] memory lockers = _lockers(service);
        uint256 slashingPercentages = _slashingPercentages(service);
        uint256 len = lockers.length;
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onRestake(msg.sender, service, slashingPercentages.get(i));
        }
    }

    function initiateUnstaking(uint256 service) external notFrozen {
        _initiateUnstaking(msg.sender, service);
        // Note: allow a service to prevent unstaking while committed, otherwise notify
        if (_isCommittedTo(msg.sender, service)) {
            _service(service).onInitializeUnstaking(msg.sender);
        } else {
            try _service(service).onInitializeUnstaking(msg.sender) {}
            catch (bytes memory revertData) {
                emit UnstakingInitiatedError(service, msg.sender, revertData);
            }
        }
    }

    function finaliseUnstaking(uint256 service) external notFrozen {
        _finaliseUnstaking(msg.sender, service);
        // Note: allow a service to prevent unstaking while committed, otherwise notify
        if (_isCommittedTo(msg.sender, service)) {
            _service(service).onFinalizeUnstaking(msg.sender);
        } else {
            try _service(service).onFinalizeUnstaking(msg.sender) {}
            catch (bytes memory revertData) {
                emit UnstakingError(service, msg.sender, revertData);
            }
        }
        uint256[] memory lockers = _lockers(service);
        uint256 slashingPercentages = _slashingPercentages(service);
        uint256 len = lockers.length;
        // Note: A service needs to trust the lockers not to revert on the call
        for (uint256 i; i < len; ++i) {
            locker(lockers[i]).onUnstake(msg.sender, service, slashingPercentages.get(i));
        }
    }

    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime) {
        scheduledTime = _initiateSlasherUpdate(_serviceId(msg.sender), newSlasher);
    }

    function finalizeSlasherUpdate() external {
        _finalizeSlasherUpdate(_serviceId(msg.sender));
    }

    function freeze(address staker) external {
        _freeze(staker, msg.sender);
    }

    function slash(address staker, uint8[] calldata percentages) external {
        _slash(staker, msg.sender, percentages);
    }

    function slashingInfo(uint256 lockerId_, address staker) external view returns (uint8 percentage) {
        return _slashingInfo(lockerId_, staker);
    }
}
