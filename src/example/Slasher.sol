// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {ISlasher} from "./interface/ISlasher.sol";
import {StakingHub} from "../StakingHub.sol";

/// @title Slasher Example With Double Signing
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
contract Slasher is ISlasher {
    address immutable service;
    uint256 immutable serviceId;
    StakingHub immutable stakingHub;

    /// @notice amount of time the staker has to prove their innocence.
    uint256 public constant GRACE_PERIOD = 3 days;

    mapping(address => uint256) public gracePeriodEnds;

    constructor(StakingHub stakingHub_, uint256 serviceId_) {
        // deployed by service in this example
        service = msg.sender;
        stakingHub = stakingHub_;
        serviceId = serviceId_;
    }

    function freeze(address staker, bytes calldata proof) public {
        require(msg.sender == service, "Slasher: Only Service ");

        _verifyProof(staker, proof);

        gracePeriodEnds[staker] = block.timestamp + GRACE_PERIOD;

        stakingHub.freeze(staker);
    }

    function proveInnocence(bytes calldata proof) public {
        require(gracePeriodEnds[msg.sender] > block.timestamp, "Slasher: outside grace period");

        if (_verifyProof(msg.sender, proof)) {
            delete gracePeriodEnds[msg.sender];
        } else {
            revert("Slasher: Proof Invalid");
        }
    }

    function slash(address staker, uint8[] calldata percentages) public {
        require(msg.sender == service, "Slasher: Only Service ");
        require(gracePeriodEnds[staker] != 0, "Slasher: No grace period started");
        require(gracePeriodEnds[staker] < block.timestamp, "Slasher: grace period has not ended");

        stakingHub.slash(staker, percentages);

        delete gracePeriodEnds[staker];
    }

    function _verifyProof(address, bytes calldata) internal pure returns (bool) {
        // validate proof here
        return true;
    }
}
