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
}
