// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {ISlasher} from "../interface/ISlasher.sol";
import {Hub} from "../StakingHub.sol";

/// @title Slasher Example With Double Signing
/// @author Polygon Labs
/// @notice A Slasher separates the freezing and slashing functionality from a Service.
contract Slasher is ISlasher {
    // TODO insert actual addresses
    address _service = address(0);
    uint256 serviceID = 0;
    Hub hub = Hub(address(0));

    /// @notice amount of time the staker has to prove their innocence.
    uint256 public GRACE_PERIOD = 4 days;
    uint256 index = 0;

    struct SlashItem {
        uint256 slashId;
        uint256 service;
        uint256 staker;
        uint8 percentage;
        uint256 gracePeriodEnd;
    }

    mapping(uint256 => SlashItem) public slashItems;
    mapping(address => uint256) private slashCounter;

    function freeze(address staker, uint8 percentage) public {
        require(msg.sender == _service, "Slasher: Only Service ");

        slashItems[index] = SlashItem(index, _service, staker, percentage, block.timestamp + GRACE_PERIOD);
        index++;
        slashCounter[staker]++;

        hub.onFreeze(staker, serviceId);
    }

    function unfreeze(address staker, uint256 slashId) public {
        require(msg.sender == _service, "Slasher: Only Service ");
        require(slashItems[slashId].staker == staker, "Slasher: Wrong Staker ");

        delete slashItems[slashId];
        slashCounter[staker]--;

        if (slashCounter[staker] == 0) {
            hub.onUnfreeze(staker, serviceId);
        }
    }

    function slash(address staker, uint256[] slashIds) public {
        require(msg.sender == _service, "Slasher: Only Service ");

        SlashItem[] memory sis;

        for (uint256 i = 0; i < slashIds.length; i++) {
            SlashItem memory slashItem = slashItems[slashIds[i]];

            if (slashItem.staker == staker && block.timestamp > slashItem.gracePeriodEnd) {
                sis.push(slashItem);
            }
        }

        hub.onSlash(staker, serviceId, sis);
    }

    function instaSlash(address staker, uint8 percentage, bytes calldata proof) public {
        // TODO
    }
}
