// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "src/StakingHub.sol";
import "src/interface/IStakingHub.sol";

abstract contract Deployed is Test, IStakingHubEvents {
    StakingHub hub;
    address[] private _lockers;
    address[] private _services;
    address[] private _slashers;
    address[] private _stakers;

    function setUp() public virtual {
        hub = new StakingHub();
        for (uint256 i; i < 10; ++i) {
            _lockers.push(address(new LockerMock()));
            _services.push(address(new ServiceMock()));
            _slashers.push(address(new SlasherMock()));
            _stakers.push(makeAddr(string.concat("staker", vm.toString(i))));
        }
    }

    function locker(uint256 id) internal view returns (address) {
        return _lockers[id - 1];
    }

    function service(uint256 id) internal view returns (address) {
        return _services[id - 1];
    }

    function slasher(uint256 id) internal view returns (address) {
        return _slashers[id - 1];
    }
}

contract StakingHubTest_Deployed is Deployed {
    function testRevert_registerLocker_NotFound() public {
        vm.prank(makeAddr("no code"));
        vm.expectRevert("Locker contract not found");
        hub.registerLocker();
    }

    function test_registerLocker() public {
        vm.prank(locker(1));
        vm.expectEmit();
        emit LockerRegistered(locker(1), 1);
        assertEq(hub.registerLocker(), 1);
    }

    function testRevert_registerService_InvalidSlasher() public {
        vm.prank(service(1));
        vm.expectRevert("Invalid slasher");
        hub.registerService(new LockerSettings[](0), 0, address(0));
    }

    function testRevert_registerService_InvalidNumberOfLockers() public {
        vm.startPrank(service(1));
        vm.expectRevert("Invalid number of lockers");
        hub.registerService(new LockerSettings[](0), 0, slasher(1));
        vm.expectRevert("Invalid number of lockers");
        hub.registerService(new LockerSettings[](33), 0, slasher(1));
    }

    function testRevert_registerService_UnsortedLockers() public {
        vm.startPrank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(2, 0);
        lockers[1] = LockerSettings(1, 0);
        vm.expectRevert("Duplicate/zero Locker or unsorted list");
        hub.registerService(lockers, 0, slasher(1));
    }

    function testRevert_registerService_InvalidSlashPercentage() public {
        vm.startPrank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(1, 0);
        lockers[1] = LockerSettings(2, 101);
        vm.expectRevert("Invalid max slash percentage");
        hub.registerService(lockers, 0, slasher(1));
    }

    function testRevert_registerService_InvalidLocker() public {
        vm.startPrank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(1, 0);
        lockers[1] = LockerSettings(2, 100);
        vm.expectRevert("Invalid locker");
        hub.registerService(lockers, 0, slasher(1));
    }

    function testRevert_registerService_NotFound() public {
        vm.prank(locker(1));
        hub.registerLocker();
        vm.prank(locker(2));
        hub.registerLocker();
        vm.prank(makeAddr("no code"));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(1, 0);
        lockers[1] = LockerSettings(2, 100);
        vm.expectRevert("Service contract not found");
        hub.registerService(lockers, 0, slasher(1));
    }

    function testRevert_registerService_InvalidNotice() public {
        vm.prank(locker(1));
        hub.registerLocker();
        vm.prank(locker(2));
        hub.registerLocker();
        vm.prank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(1, 0);
        lockers[1] = LockerSettings(2, 100);
        vm.expectRevert("Invalid unsubscription notice");
        hub.registerService(lockers, 0, slasher(1));
    }

    function test_registerService() public {
        vm.prank(locker(1));
        hub.registerLocker();
        vm.prank(locker(2));
        hub.registerLocker();
        vm.prank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(1, 0);
        lockers[1] = LockerSettings(2, 100);
        uint256[] memory lockerIds = new uint256[](2);
        lockerIds[0] = lockers[0].lockerId;
        lockerIds[1] = lockers[1].lockerId;
        vm.expectEmit();
        emit ServiceRegistered(service(1), 1, lockerIds, 0x6400, 1);
        vm.expectEmit();
        emit SlasherUpdated(1, slasher(1));
        assertEq(hub.registerService(lockers, 1, slasher(1)), 1);
    }
}

abstract contract Registered is Deployed {
    /*
    Set up explanation:
        - Service ID tells how many lockers the service uses (starting from locker ID 1).
        - The maximum slashing percentage for a locker is service ID * 10 + locker ID (service ID 10 slashes 100% on all lockers).
        - Unsubscription notice periods are of length service ID days.

    Example for service ID 3:
        - Uses locker IDs 1, 2, 3.
        - Maximum slashing percentages are 31%, 32%, 33%.
        - Unsubscription notice period is 3 days.
    */
    function setUp() public virtual override {
        super.setUp();
        for (uint256 l = 1; l <= 10; ++l) {
            vm.prank(locker(l));
            hub.registerLocker();
        }
        for (uint256 s = 1; s <= 10; ++s) {
            vm.prank(service(s));
            LockerSettings[] memory lockers = new LockerSettings[](s);
            for (uint256 l = 1; l <= s; ++l) {
                lockers[l - 1] = LockerSettings(l, s != 10 ? uint8(s * 10 + l) : 100);
            }
            hub.registerService(lockers, uint40(s * 1 days), slasher(s));
        }
    }
}

contract StakingHubTest_Registered is Registered {
    function testRevert_registerLocker_AlreadyRegistered() public {
        vm.startPrank(locker(10));
        vm.expectRevert("Locker already registered");
        hub.registerLocker();
    }

    function testRevert_registerService_AlreadyRegistered() public {
        vm.startPrank(service(10));
        LockerSettings[] memory lockers = new LockerSettings[](1);
        lockers[0] = LockerSettings(10, 0);
        vm.expectRevert("Service already registered");
        hub.registerService(lockers, 1, slasher(1));
    }

    function testRevert_initiateSlasherUpdate_NotRegistered() public {
        vm.expectRevert("Service not registered");
        hub.initiateSlasherUpdate(address(0));
    }

    function testRevert_initiateSlasherUpdate_InvalidSlasher() public {
        vm.prank(service(1));
        vm.expectRevert("Invalid slasher");
        hub.initiateSlasherUpdate(address(0));
    }

    function testRevert_initiateSlasherUpdate_SameSlasher() public {
        vm.prank(service(1));
        vm.expectRevert("Same slasher");
        hub.initiateSlasherUpdate(slasher(1));
    }

    function test_initiateSlasherUpdate() public {
        vm.prank(service(1));
        vm.expectEmit();
        emit SlasherUpdateInitiated(1, slasher(2), uint40(block.timestamp + 7 days + 1 days));
        hub.initiateSlasherUpdate(slasher(2));
    }

    function testRevert_initiateSlasherUpdate_AlreadyInitiated() public {
        vm.startPrank(service(1));
        hub.initiateSlasherUpdate(slasher(2));
        vm.expectRevert("Slasher update already initiated");
        hub.initiateSlasherUpdate(slasher(2));
    }

    function testRevert_finalizeSlasherUpdate_NotRegistered() public {
        vm.expectRevert("Service not registered");
        hub.finalizeSlasherUpdate();
    }

    function testRevert_finalizeSlasherUpdate_NotInitiated() public {
        vm.prank(service(1));
        vm.expectRevert("Slasher update not initiated");
        hub.finalizeSlasherUpdate();
    }

    function testRevert_finalizeSlasherUpdate_NotYet() public {
        vm.startPrank(service(1));
        hub.initiateSlasherUpdate(slasher(2));
        skip(7 days + 1 days - 1);
        vm.expectRevert("Slasher cannot be updated yet");
        hub.finalizeSlasherUpdate();
    }

    function testRevert_finalizeSlasherUpdate() public {
        vm.startPrank(service(1));
        hub.initiateSlasherUpdate(slasher(2));
        skip(7 days + 1 days);
        vm.expectEmit();
        emit SlasherUpdated(1, slasher(2));
        hub.finalizeSlasherUpdate();
        vm.expectRevert("Slasher update not initiated");
        hub.finalizeSlasherUpdate();
    }
}

contract LockerMock {}

contract ServiceMock {}

contract SlasherMock {}
