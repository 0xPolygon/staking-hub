// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILocker} from "../interface/ILocker.sol";
import {StakingLayer} from "../StakingLayer.sol";

abstract contract Locker is ILocker {
    address internal immutable _stakingLayer;
    address internal immutable _burnAddress;

    uint256 internal _id;
    mapping(address staker => uint256 balance) internal _balance;
    mapping(address staker => uint256 votingPower) internal _votingPower;
    uint256 internal _totalSupply;
    uint256 internal _totalVotingPower;

    modifier burner() {
        uint256 slashedPercentage = StakingLayer(_stakingLayer).slashedPercentage(_id, msg.sender);
        if (slashedPercentage > 0) _burn(slashedPercentage);
        _;
    }

    constructor(address stakingLayer, address burnAddress) {
        _stakingLayer = stakingLayer;
        _burnAddress = burnAddress;
    }

    function registerLocker() external {
        _id = StakingLayer(_stakingLayer).registerLocker();
    }

    function deposit(uint256 amount) external burner {
        (uint256 balanceIncrease, uint256 votingPowerIncrease) = _deposit(amount);
        _balance[msg.sender] += balanceIncrease;
        _totalSupply += balanceIncrease;
        _votingPower[msg.sender] += votingPowerIncrease;
        _totalVotingPower += votingPowerIncrease;
    }

    // NOTE Are we limiting subscriptions if risk above 100%?
    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external burner {
        require(msg.sender == _stakingLayer, "Unauthorized");
        _trackSubscription(staker, service, maxSlashPercentage);
        _onSubscribe(staker, service, maxSlashPercentage);
    }

    function onUnsubscribe(address staker, uint256 service) external burner {
        require(msg.sender == _stakingLayer, "Unauthorized");
        _untrackSubscription(staker, service);
        _onUnsubscribe(staker, service);
    }

    // TODO Add delay
    function withdraw(uint256 amount) external burner {
        require(amount <= _safeBalanceOf(msg.sender), "Amount exceeds safe balance");
        (uint256 balanceDecrease, uint256 votingPowerDecrease) = _withdraw(amount);
        _balance[msg.sender] += balanceDecrease;
        _totalSupply += balanceDecrease;
        _votingPower[msg.sender] += votingPowerDecrease;
        _totalVotingPower += votingPowerDecrease;
    }

    function balanceOf(address staker) external view returns (uint256 balance) {
        return _balanceOf(staker, StakingLayer(_stakingLayer).slashedPercentage(_id, staker));
    }

    function votingPowerOf(address staker) external view returns (uint256 votingPower) {
        return _votingPower[staker];
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function totalVotingPower() external view returns (uint256) {
        return _totalVotingPower;
    }

    function _deposit(uint256 amount) internal virtual returns (uint256 balanceIncrease, uint256 votingPowerIncrease);
    function _trackSubscription(address staker, uint256 service, uint8 maxSlashPercentage) internal virtual;
    function _onSubscribe(address staker, uint256 service, uint256 maxSlashPercentage) internal virtual;
    function _untrackSubscription(address staker, uint256 service) internal virtual;
    function _onUnsubscribe(address staker, uint256 service) internal virtual;
    function _safeBalanceOf(address staker) internal virtual returns (uint256 safeBalance);
    function _withdraw(uint256 amount) internal virtual returns (uint256 balanceDecrease, uint256 votingPowerDecrease);
    function _balanceOf(address staker, uint256 slashedPercentage) internal view virtual returns (uint256 balance);

    function _burn(uint256 percenage) private {
        // TODO
    }
}
