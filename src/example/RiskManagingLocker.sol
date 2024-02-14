// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

import {ERC20Locker} from "./ERC20Locker.sol";

contract RiskManagingLocker is ERC20Locker {
    uint256 public immutable maxRisk;

    mapping(address => uint256) public stakerRisk;

    constructor(address _underlying, address stakingHub, address burnAddress, uint256 _maxRisk) ERC20Locker(_underlying, stakingHub, burnAddress) {
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
