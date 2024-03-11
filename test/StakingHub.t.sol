// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "src/StakingHub.sol";
import "src/interface/IStakingHub.sol";

contract StakingHubTest is Test, IStakingHubEvents {
    StakingHub hub;
    address[] lockers;
    address[] services;
    address[] slashers;

    function setUp() public {
        hub = new StakingHub();
        for (uint256 i; i < 10; ++i) {
            lockers.push(address(new LockerMock()));
            services.push(address(new ServiceMock()));
            slashers.push(address(new SlasherMock()));
        }
    }

    function testRevert_registerLocker_NoCode() public {
        vm.prank(makeAddr("no code"));
        vm.expectRevert("Locker contract not found");
        hub.registerLocker();
    }

    function test_registerLocker() public {
        vm.prank(lockers[0]);
        vm.expectEmit();
        emit LockerRegistered(lockers[0], 1);
        assertEq(hub.registerLocker(), 1);
    }

    function testRevert_registerLocker_AlreadyRegistered() public {
        vm.startPrank(lockers[0]);
        hub.registerLocker();
        vm.expectRevert("Locker already registered");
        hub.registerLocker();
    }

    function testRevert_registerService_InvalidSlasher() public {
        vm.prank(services[0]);
        vm.expectRevert("Invalid slasher");
        hub.registerService(new LockerSettings[](0), 0, address(0));
    }

    function testRevert_registerService_InvalidNumberOfLockers() public {
        vm.startPrank(services[0]);
        vm.expectRevert("Invalid number of lockers");
        hub.registerService(new LockerSettings[](0), 0, slashers[0]);
        vm.expectRevert("Invalid number of lockers");
        hub.registerService(new LockerSettings[](33), 0, slashers[0]);
    }

    function testRevert_registerService_UnsortedLockers() public {
        vm.startPrank(services[0]);
        LockerSettings[] memory lockers_ = new LockerSettings[](2);
        lockers_[0] = LockerSettings(2, 0);
        lockers_[1] = LockerSettings(1, 0);
        vm.expectRevert("Duplicate/zero Locker or unsorted list");
        hub.registerService(lockers_, 0, slashers[0]);
    }

    function testRevert_registerService_InvalidSlashPercentage() public {
        vm.startPrank(services[0]);
        LockerSettings[] memory lockers_ = new LockerSettings[](2);
        lockers_[0] = LockerSettings(1, 0);
        lockers_[1] = LockerSettings(2, 101);
        vm.expectRevert("Invalid max slash percentage");
        hub.registerService(lockers_, 0, slashers[0]);
    }

    function testRevert_registerService_InvalidLocker() public {
        vm.startPrank(services[0]);
        LockerSettings[] memory lockers_ = new LockerSettings[](2);
        lockers_[0] = LockerSettings(1, 0);
        lockers_[1] = LockerSettings(2, 100);
        vm.expectRevert("Invalid locker");
        hub.registerService(lockers_, 0, slashers[0]);
    }

    function testRevert_registerService_NoCode() public {
        vm.prank(lockers[0]);
        hub.registerLocker();
        vm.prank(lockers[1]);
        hub.registerLocker();
        vm.prank(makeAddr("no code"));
        LockerSettings[] memory lockers_ = new LockerSettings[](2);
        lockers_[0] = LockerSettings(1, 0);
        lockers_[1] = LockerSettings(2, 100);
        vm.expectRevert("Service contract not found");
        hub.registerService(lockers_, 0, slashers[0]);
    }

    function testRevert_registerService_ZeroNotice() public {
        vm.prank(lockers[0]);
        hub.registerLocker();
        vm.prank(lockers[1]);
        hub.registerLocker();
        vm.prank(services[0]);
        LockerSettings[] memory lockers_ = new LockerSettings[](2);
        lockers_[0] = LockerSettings(1, 0);
        lockers_[1] = LockerSettings(2, 100);
        vm.expectRevert("Invalid unsubscription notice");
        hub.registerService(lockers_, 0, slashers[0]);
    }

    function test_registerService() public {
        vm.prank(lockers[0]);
        hub.registerLocker();
        vm.prank(lockers[1]);
        hub.registerLocker();
        vm.prank(services[0]);
        LockerSettings[] memory lockers_ = new LockerSettings[](2);
        lockers_[0] = LockerSettings(1, 0);
        lockers_[1] = LockerSettings(2, 100);
        uint256[] memory lockerIds = new uint256[](2);
        lockerIds[0] = lockers_[0].lockerId;
        lockerIds[1] = lockers_[1].lockerId;
        vm.expectEmit();
        emit ServiceRegistered(services[0], 1, lockerIds, 0x6400, 1);
        hub.registerService(lockers_, 1, slashers[0]);
    }

    function testRevert_registerService_AlreadyRegistered() public {
        vm.prank(lockers[0]);
        hub.registerLocker();
        vm.startPrank(services[0]);
        LockerSettings[] memory lockers_ = new LockerSettings[](1);
        lockers_[0] = LockerSettings(1, 0);
        uint256[] memory lockerIds = new uint256[](1);
        lockerIds[0] = lockers_[0].lockerId;
        hub.registerService(lockers_, 1, slashers[0]);
        vm.expectRevert("Service already registered");
        hub.registerService(lockers_, 1, slashers[0]);
    }
}

contract LockerMock {}

contract ServiceMock {}

contract SlasherMock {}
