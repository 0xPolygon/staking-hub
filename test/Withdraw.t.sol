// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ERC20LockerExample} from "../src/example/ERC20LockerExample.sol";
import {ERC20Locker} from "../src/template/ERC20Locker.sol";
import {StakingHub} from "../src/StakingHub.sol";
import {LockerSettings} from "../src/interface/IStakingHub.sol";
import {ILocker} from "../src/interface/ILocker.sol";
import {ServicePoS} from "../src/example/ServicePoS.sol";
import {Slasher} from "../src/example/Slasher.sol";

contract Withdraw is Test {
    ERC20Mock tkn;
    StakingHub stakingHub;
    ERC20LockerExample locker;
    ServicePoS service;
    ServicePoS service1;
    ServicePoS service2;
    LockerSettings[] settings;
    ERC20Locker[] lockers;

    uint40 constant WEEK = 7 days;

    function setUp() public {
        tkn = new ERC20Mock();
        stakingHub = new StakingHub();
        locker = new ERC20LockerExample(address(tkn), address(0));
        locker.initialize(address(stakingHub));
        uint256 lockerId = locker.registerLocker();

        settings.push(LockerSettings(lockerId, 20));
        lockers.push(locker);
        service = new ServicePoS(address(stakingHub), lockers);
        service.init(settings, WEEK);
        service1 = new ServicePoS(address(stakingHub), lockers);
        service1.init(settings, WEEK);
        service2 = new ServicePoS(address(stakingHub), lockers);
        service2.init(settings, WEEK);

        // subscribe to services 0 and 1
        stakingHub.subscribe(service.id(), uint40(vm.getBlockTimestamp()) + WEEK);
        stakingHub.subscribe(service1.id(), uint40(vm.getBlockTimestamp()) + WEEK);
    }

    function test_initiateWithdrawal(uint256 amount, uint256 withdraw) external {
        vm.assume(amount > withdraw);
        vm.assume(withdraw > 0);
        vm.assume(amount > 0);

        mintAndApprove(amount);
        locker.deposit(amount);
        assertDeposit(address(this), amount);

        vm.expectEmit(true, true, false, false);
        emit ILocker.BalanceChanged(address(this), amount - withdraw);

        locker.initiateWithdrawal(withdraw);

        // tokens have not been payed back yet
        assertEq(0, tkn.balanceOf(address(this)));
        // balance and totalSupply have decreased
        assertEq(amount - withdraw, locker.balanceOf(address(this)));
        assertEq(amount - withdraw, locker.totalSupply());

        assertEq(amount - withdraw, locker.balanceOf(address(this), service.id()));
        assertEq(amount - withdraw, locker.totalSupply(service.id()));

        assertEq(amount - withdraw, locker.balanceOf(address(this), service1.id()));
        assertEq(amount - withdraw, locker.totalSupply(service1.id()));
    }

    function test_initiateWithdrawal_alreadyInitialised(uint256 amount, uint256 withdraw) external {
        vm.assume(amount > 0);
        vm.assume(withdraw > 0 && withdraw < type(uint128).max);
        vm.assume(amount > withdraw * 2);

        mintAndApprove(amount);
        locker.deposit(amount);
        assertDeposit(address(this), amount);

        locker.initiateWithdrawal(withdraw);
        vm.expectRevert("Withdrawal already initiated");
        locker.initiateWithdrawal(withdraw);
    }

    function test_initiateWithdrawal_insufficientBalance(uint256 amount) external {
        vm.assume(amount > 0 && amount < type(uint256).max - 1);

        mintAndApprove(amount);
        locker.deposit(amount);
        assertDeposit(address(this), amount);

        vm.expectRevert("Insufficient balance");
        locker.initiateWithdrawal(amount + 1);
    }

    function test_initiateWithdrawal_whenFrozen(uint256 amount) external {
        vm.assume(amount > 0);

        mintAndApprove(amount);
        locker.deposit(amount);
        assertDeposit(address(this), amount);

        service.freeze(address(this), "0x");

        vm.expectRevert("Staker is frozen");
        locker.initiateWithdrawal(amount);
    }

    function test_finalizeWithdrawal_whenFrozen(uint256 amount) external {
        vm.assume(amount > 0);

        mintAndApprove(amount);
        locker.deposit(amount);

        locker.initiateWithdrawal(amount);

        service.freeze(address(this), "0x");

        vm.expectRevert("Staker is frozen");
        locker.finalizeWithdrawal();
    }

    function test_finalizeWithdrawal_notInitiated(uint256 amount) external {
        vm.assume(amount > 0);

        mintAndApprove(amount);
        locker.deposit(amount);

        vm.expectRevert("Withrawal not initiated");
        locker.finalizeWithdrawal();
    }

    function test_finalizeWithdrawal_tooSoon(uint256 amount) external {
        vm.assume(amount > 0);

        mintAndApprove(amount);
        locker.deposit(amount);

        locker.initiateWithdrawal(amount);

        vm.expectRevert("Cannot withdraw at this time");
        locker.finalizeWithdrawal();
    }

    function test_finalizeWithdrawal(uint256 amount) external {
        vm.assume(amount > 0);

        mintAndApprove(amount);
        locker.deposit(amount);
        assertDeposit(address(this), amount);

        locker.initiateWithdrawal(amount);

        vm.expectEmit(true, true, false, false);
        emit ILocker.Withdrawn(address(this), amount);

        vm.warp(block.timestamp + WEEK + 1);
        locker.finalizeWithdrawal();

        assertEq(amount, tkn.balanceOf(address(this)));
    }

    function deposit(uint256 amount) private {
        mintAndApprove(amount);

        locker.deposit(amount);
    }

    function depositFor(address user, uint256 amount) private {
        vm.assume(user != address(0));
        mintAndApprove(amount);

        locker.depositFor(user, amount);
    }

    function mintAndApprove(uint256 amount) private {
        tkn.mint(address(this), amount);
        tkn.approve(address(locker), amount);
    }

    function assertDeposit(address user, uint256 amount) private view {
        assertEq(0, tkn.balanceOf(user));
        assertEq(amount, locker.balanceOf(user));

        // total supply of locker is updated
        assertEq(amount, locker.totalSupply());

        assertEq(amount, locker.balanceOf(user, service.id()));
        assertEq(amount, locker.totalSupply(service.id()));

        assertEq(amount, locker.balanceOf(user, service1.id()));
        assertEq(amount, locker.totalSupply(service1.id()));
        // not subscribed to service2
        assertEq(0, locker.balanceOf(user, service2.id()));
        assertEq(0, locker.totalSupply(service2.id()));
    }
}
