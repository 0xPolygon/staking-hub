// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*
import {ISlasher} from "./interface/ISlasher.sol";
import {SlashingInput, StakingHub} from "../StakingHub.sol";

/// @title Slasher Example With Double Signing
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
contract Slasher is ISlasher {
    address immutable service;
    uint256 immutable serviceId;
    StakingHub immutable stakingHub;

    /// @notice amount of time the staker has to prove their innocence.
    uint256 public constant GRACE_PERIOD = 4 days;

    mapping(address => uint256) public gracePeriodEnds;

    constructor(StakingHub stakingHub_) {
        // deployed by service in this example
        stakingHub = stakingHub_;
        service = msg.sender;
        serviceId = stakingHub_.services(msg.sender);
    }

    function freeze(address staker, bytes calldata proof) public {
        require(msg.sender == service, "Slasher: Only Service ");

        _verifyProof(staker, proof);

        gracePeriodEnds[staker] = block.timestamp + GRACE_PERIOD;

        stakingHub.onFreeze(serviceId, staker);
    }

    function unfreeze(address staker) public {
        require(msg.sender == service, "Slasher: Only Service ");
        require(gracePeriodEnds[staker] != 0, "Slasher: Wrong Staker");

        delete gracePeriodEnds[staker];

        stakingHub.onUnfreeze(serviceId, staker);
    }

    function proveInnocence(bytes calldata proof) public {
        require(gracePeriodEnds[msg.sender] != 0, "Slasher: Wrong Staker");
        require(gracePeriodEnds[msg.sender] > block.timestamp, "Slasher: Grace Period Ended");

        if (_verifyProof(msg.sender, proof)) {
            delete gracePeriodEnds[msg.sender];
            stakingHub.onUnfreeze(serviceId, msg.sender);
        } else {
            revert("Slasher: Proof Invalid");
        }
    }

    function slash(address staker, uint8 percentage) public {
        require(msg.sender == service, "Slasher: Only Service ");
        require(gracePeriodEnds[staker] != 0, "Slasher: Wrong Staker");

        delete gracePeriodEnds[staker];

        SlashingInput memory slashingInputs = SlashingInput({lockerId: 1, percentage: percentage});

        SlashingInput[] memory input = new SlashingInput[](1);
        input[0] = slashingInputs;

        stakingHub.onSlash(serviceId, staker, input);
    }

    function _verifyProof(address, bytes calldata) internal pure returns (bool) {
        // validate proof here
        return true;
    }
}
*/
