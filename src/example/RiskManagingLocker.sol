// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import {ERC20LockerExample} from "./ERC20LockerExample.sol";

contract RiskManagingLocker is ERC20LockerExample {
    uint256 public immutable maxRisk;

    mapping(address => uint256) public stakerRisk;

    constructor(address _underlying, address stakingHub, address burnAddress, uint256 _maxRisk) ERC20LockerExample(_underlying, stakingHub, burnAddress) {
        maxRisk = _maxRisk;
    }

    function _onSubscribe(address staker, uint256, uint8 maxSlashPercentage) internal override {
        stakerRisk[staker] += maxSlashPercentage;
        if (stakerRisk[staker] > maxRisk) {
            revert("Risk exceeds maximum acceptable risk");
        }
    }

    function _onUnsubscribe(address staker, uint256, uint8 maxSlashPercentage) internal override {
        stakerRisk[staker] -= maxSlashPercentage;
    }
}
