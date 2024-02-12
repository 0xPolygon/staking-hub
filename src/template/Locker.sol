// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ILocker} from "../interface/ILocker.sol";
import {StakingLayer} from "../StakingLayer.sol";

abstract contract Locker is ILocker {
    struct StakerData {
        uint256 balance;
        uint256 votingPower;
        uint8 risk;
        uint256 initialWithdrawAmount;
        uint256 withdrawableFrom;
    }

    uint256 internal constant STAKER_WITHDRAWAL_DELAY = 7 days;

    address internal immutable _stakingLayer;
    address internal immutable _burnAddress;

    mapping(address staker => StakerData) private _staker;
    uint256 private _totalSupply;
    uint256 private _totalVotingPower;

    uint256 internal _id;

    modifier burner(address staker) {
        uint256 slashedPercentage = StakingLayer(_stakingLayer).slashedPercentage(_id, staker);
        if (slashedPercentage > 0) {
            _burn(staker, slashedPercentage);
            StakingLayer(_stakingLayer).onBurn(staker);
        }
        _;
    }

    constructor(address stakingLayer, address burnAddress) {
        _stakingLayer = stakingLayer;
        _burnAddress = burnAddress;
    }

    function registerLocker() external {
        _id = StakingLayer(_stakingLayer).registerLocker();
    }

    function deposit(uint256 amount) external burner(msg.sender) {
        (uint256 newBalance, uint256 newTotalSupply, uint256 newVotingPower, uint256 newTotalVotingPower) = _deposit(amount);
        _staker[msg.sender].balance = newBalance;
        _totalSupply = newTotalSupply;
        _staker[msg.sender].votingPower = newVotingPower;
        _totalVotingPower = newTotalVotingPower;
    }

    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage, uint8 maxRisk) external burner(staker) {
        require(msg.sender == _stakingLayer, "Unauthorized");
        _staker[staker].risk += maxSlashPercentage;
        require(_staker[staker].risk < maxRisk, "Risk exceeds max risk");
        _onSubscribe(staker, service, maxSlashPercentage, maxRisk);
    }

    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external burner(staker) {
        require(msg.sender == _stakingLayer, "Unauthorized");
        _staker[staker].risk -= maxSlashPercentage;
        _onUnsubscribe(staker, service, maxSlashPercentage);
    }

    function initiateWithdrawal(uint256 amount) external {
        initiateWithdrawal(amount, false);
    }

    function initiateWithdrawal(uint256 amount, bool force) public burner(msg.sender) {
        if (!force) require(_staker[msg.sender].initialWithdrawAmount == 0, "Withdrawal already initiated");
        require(amount != 0, "Invalid amount");
        require(!_isAmountGt(amount, _safeBalanceOf(msg.sender)), "Amount exceeds safe balance");
        _staker[msg.sender].initialWithdrawAmount = amount;
        _staker[msg.sender].withdrawableFrom = block.timestamp + STAKER_WITHDRAWAL_DELAY;
    }

    function finalizeWithdrawal() external burner(msg.sender) returns (uint256 amount) {
        amount = _staker[msg.sender].initialWithdrawAmount;
        require(amount != 0, "Withrawal not initiated");
        require(_staker[msg.sender].withdrawableFrom > block.timestamp, "Cannot withdraw at this time");
        if (_isAmountGt(amount, _safeBalanceOf(msg.sender))) amount = _safeBalanceOf(msg.sender);
        require(amount != 0, "Nothing to withdraw");
        delete _staker[msg.sender].initialWithdrawAmount;
        (uint256 newBalance, uint256 newTotalSupply, uint256 newVotingPower, uint256 newTotalVotingPower) = _withdraw(amount);
        _staker[msg.sender].balance = newBalance;
        _totalSupply = newTotalSupply;
        _staker[msg.sender].votingPower = newVotingPower;
        _totalVotingPower = newTotalVotingPower;
    }

    function balanceOf(address staker) public view returns (uint256 balance) {
        return _balanceOf(staker, StakingLayer(_stakingLayer).slashedPercentage(_id, staker));
    }

    function votingPowerOf(address staker) public view returns (uint256 votingPower) {
        return _staker[staker].votingPower;
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function totalVotingPower() public view returns (uint256) {
        return _totalVotingPower;
    }

    function _balance(address staker) internal view returns (uint256) {
        return _staker[staker].balance;
    }

    function _risk(address staker) internal view returns (uint8) {
        return _staker[staker].risk;
    }

    function _burn(address staker, uint256 percentage) internal virtual;
    function _deposit(uint256 amount)
        internal
        virtual
        returns (uint256 newBalance, uint256 newTotalSupply, uint256 newVotingPower, uint256 newTotalVotingPower);
    function _onSubscribe(address staker, uint256 service, uint256 maxSlashPercentage, uint8 maxRisk) internal virtual;
    function _onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) internal virtual;
    function _isAmountGt(uint256 a, uint256 b) internal virtual returns (bool isGreaterThan);
    function _withdraw(uint256 amount)
        internal
        virtual
        returns (uint256 newBalance, uint256 newTotalSupply, uint256 newVotingPower, uint256 newTotalVotingPower);
    function _balanceOf(address staker, uint256 slashedPercentage) internal view virtual returns (uint256 balance);
    function _safeBalanceOf(address staker) internal view virtual returns (uint256 safeBalance);
}
