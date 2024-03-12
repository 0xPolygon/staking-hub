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

contract DepositTest is Test {
    ERC20Mock public tkn;
    StakingHub public stakingHub;
    ERC20LockerExample public locker;
    ServicePoS public service;
    Slasher public slasher;
    LockerSettings[] settings;
    ERC20Locker[] lockers;

    uint40 constant WEEK = 7 days;

    function setUp() public {
        tkn = new ERC20Mock();
        stakingHub = new StakingHub();
        locker = new ERC20LockerExample(address(tkn), address(stakingHub), address(0));
        uint256 lockerId = locker.registerLocker();

        settings.push(LockerSettings(lockerId, 20));
        lockers.push(locker);
        service = new ServicePoS(address(stakingHub), lockers);
        service.init(settings, WEEK);

        slasher = Slasher(service.slasher());
    }

    function test_deposit(uint256 amount) external {
        deposit(amount);

        assertDeposit(address(this), amount);
    }

    function test_depositFor(address user, uint256 amount) external {
        depositFor(user, amount);

        assertDeposit(user, amount);
    }

    function test_deposit_whenFrozen(uint256 amount) external {
        stakingHub.subscribe(service.id(), WEEK);

        service.freeze(address(this), "0x");

        mintAndApprove(amount);
        vm.expectRevert("Staker is frozen");
        locker.deposit(amount);
    }

    function test_depositFor_whenFrozen(address user, uint256 amount) external {
        vm.assume(user != address(0));
        uint256 id = service.id();
        vm.prank(user);
        stakingHub.subscribe(id, WEEK);

        service.freeze(user, "0x");

        mintAndApprove(amount);
        vm.expectRevert("Staker is frozen");
        locker.depositFor(user, amount);
    }

    // services subscribed to by this user should have the total balances updated
    function test_deposit_whenSubscribed(uint256 amount) external {
        vm.assume(amount > 0);
        stakingHub.subscribe(service.id(), WEEK);

        mintAndApprove(amount);
        locker.deposit(amount);

        assertDeposit(address(this), amount);

        assertEq(amount, locker.totalSupply(service.id()));
    }

    function test_deposit_whenSubscribedToMultiple(uint256 amount) external {
        vm.assume(amount > 0);
        ServicePoS service1 = new ServicePoS(address(stakingHub), lockers);
        service1.init(settings, WEEK);
        ServicePoS service2 = new ServicePoS(address(stakingHub), lockers);
        service2.init(settings, WEEK);

        stakingHub.subscribe(service.id(), WEEK);
        stakingHub.subscribe(service1.id(), WEEK);

        mintAndApprove(amount);
        locker.deposit(amount);

        assertDeposit(address(this), amount);

        assertEq(amount, locker.totalSupply(service.id()));
        assertEq(amount, locker.totalSupply(service1.id()));
        // not subscribed to service2
        assertEq(0, locker.totalSupply(service2.id()));
    }

    function deposit(uint256 amount) private {
        mintAndApprove(amount);

        vm.expectEmit(true, true, false, false);
        emit ILocker.BalanceChanged(address(this), amount);

        locker.deposit(amount);
    }

    function depositFor(address user, uint256 amount) private {
        vm.assume(user != address(0));
        mintAndApprove(amount);

        vm.expectEmit(true, true, false, false);
        emit ILocker.BalanceChanged(user, amount);

        locker.depositFor(user, amount);
    }

    function mintAndApprove(uint256 amount) private {
        tkn.mint(address(this), amount);
        tkn.approve(address(locker), amount);
    }

    function assertDeposit(address user, uint256 amount) private {
        assertEq(0, tkn.balanceOf(user));
        assertEq(amount, locker.balanceOf(user));

        // total supply of locker is updated
        assertEq(amount, locker.totalSupply());
    }
}
