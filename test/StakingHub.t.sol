// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

import "forge-std/Test.sol";

import "src/StakingHub.sol";
import "src/interface/IStakingHub.sol";
import "src/interface/IService.sol";
import "src/interface/ILocker.sol";

abstract contract Deployed is Test, IStakingHubEvents {
    StakingHub hub;
    address[] private _lockers;
    address[] private _services;
    address[] private _slashers;
    address[] private _stakers;
    address troll;

    /*
    Set up explanation:
        - Deploys Hub, 10 lockers, 10 services, 10 slashers.
        - Creates 10 stakers and a troll (🧌).
    */
    function setUp() public virtual {
        hub = new StakingHub();
        for (uint256 i; i < 10; ++i) {
            _lockers.push(address(new LockerMock()));
            _services.push(address(new ServiceMock()));
            _slashers.push(address(new SlasherMock()));
            _stakers.push(makeAddr(string.concat("staker", vm.toString(i))));
        }
        troll = makeAddr(unicode"🧌");
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

    function staker(uint256 id) internal view returns (address) {
        return _stakers[id - 1];
    }
}

contract StakingHubTest_Deployed is Deployed {
    function testRevert_registerLocker_NotFound() public {
        vm.prank(troll);
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
        vm.prank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(2, 0);
        lockers[1] = LockerSettings(1, 0);
        vm.expectRevert("Duplicate/zero Locker or unsorted list");
        hub.registerService(lockers, 0, slasher(1));
    }

    function testRevert_registerService_InvalidSlashPercentage() public {
        vm.prank(service(1));
        LockerSettings[] memory lockers = new LockerSettings[](2);
        lockers[0] = LockerSettings(1, 0);
        lockers[1] = LockerSettings(2, 101);
        vm.expectRevert("Invalid max slash percentage");
        hub.registerService(lockers, 0, slasher(1));
    }

    function testRevert_registerService_InvalidLocker() public {
        vm.prank(service(1));
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
        vm.prank(troll);
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
        - Slasher is slasher #service ID.

    Example for service ID 3:
        - Uses locker IDs 1, 2, 3.
        - Maximum slashing percentages are 31%, 32%, 33%.
        - Unsubscription notice period is 3 days.
        - Slasher is slasher #3.
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
                lockers[l - 1] = LockerSettings(l, maxSlashPercentage(s, l));
            }
            hub.registerService(lockers, uint40(s * 1 days), slasher(s));
        }
    }

    function maxSlashPercentage(uint256 serviceId, uint256 lockerId) internal pure returns (uint8) {
        require(serviceId <= 10, "Unknown service");
        require(lockerId <= 10, "Unknown locker");
        return serviceId != 10 ? uint8(serviceId * 10 + lockerId) : 100;
    }
}

contract StakingHubTest_Registered is Registered {
    function testRevert_registerLocker_AlreadyRegistered() public {
        vm.prank(locker(10));
        vm.expectRevert("Locker already registered");
        hub.registerLocker();
    }

    function testRevert_registerService_AlreadyRegistered() public {
        vm.prank(service(10));
        LockerSettings[] memory lockers = new LockerSettings[](1);
        lockers[0] = LockerSettings(10, 0);
        vm.expectRevert("Service already registered");
        hub.registerService(lockers, 1, slasher(1));
    }

    function testRevert_initiateSlasherUpdate_NotRegistered() public {
        vm.prank(troll);
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
        emit SlasherUpdateInitiated(1, slasher(2), uint40(vm.getBlockTimestamp() + 7 days + 1 days));
        hub.initiateSlasherUpdate(slasher(2));
    }

    function testRevert_initiateSlasherUpdate_AlreadyInitiated() public {
        vm.startPrank(service(1));
        hub.initiateSlasherUpdate(slasher(2));
        vm.expectRevert("Slasher update already initiated");
        hub.initiateSlasherUpdate(slasher(2));
    }

    function testRevert_finalizeSlasherUpdate_NotRegistered() public {
        vm.prank(troll);
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

    function test_finalizeSlasherUpdate() public {
        vm.startPrank(service(1));
        hub.initiateSlasherUpdate(slasher(2));
        skip(7 days + 1 days);
        vm.expectEmit();
        emit SlasherUpdated(1, slasher(2));
        hub.finalizeSlasherUpdate();
    }

    function testRevert_terminate_NotRegistered() public {
        vm.prank(troll);
        vm.expectRevert("Service not registered");
        hub.terminate(staker(1));
    }

    function testRevert_terminate_NotSubscribed() public {
        vm.prank(service(1));
        vm.expectRevert("Not subscribed");
        hub.terminate(staker(1));
    }

    function test_terminate() public {
        vm.prank(staker(1));
        hub.subscribe(2, 0);
        vm.prank(service(2));
        for (uint256 l = 1; l <= 2; ++l) {
            vm.expectCall(locker(l), abi.encodeCall(ILocker.onUnsubscribe, (staker(1), 2, maxSlashPercentage(2, l))));
        }
        vm.expectEmit();
        emit Unsubscribed(staker(1), 2);
        hub.terminate(staker(1));
    }

    function testRevert_freeze_NotSubscribed() public {
        vm.prank(slasher(1));
        vm.expectRevert("Not subscribed");
        hub.freeze(staker(1));
    }

    function test_freeze() public {
        vm.prank(staker(1));
        hub.subscribe(1, 0);
        vm.prank(slasher(1));
        vm.expectEmit();
        emit StakerFrozen(staker(1), 1, vm.getBlockTimestamp() + 7 days);
        hub.freeze(staker(1));
    }

    function testRevert_freeze_AlreadyFrozen() public {
        vm.prank(staker(1));
        hub.subscribe(1, 0);
        vm.startPrank(slasher(1));
        hub.freeze(staker(1));
        skip(7 days - 1);
        vm.expectRevert("Already frozen by this service");
        hub.freeze(staker(1));
    }

    function test_freeze_NewPeriod() public {
        vm.prank(staker(1));
        hub.subscribe(1, 0);
        vm.startPrank(slasher(1));
        hub.freeze(staker(1));
        skip(7 days);
        vm.expectEmit();
        emit StakerFrozen(staker(1), 1, vm.getBlockTimestamp() + 7 days);
        hub.freeze(staker(1));
    }

    function test_freeze_ExtendPeriod() public {
        vm.startPrank(staker(1));
        hub.subscribe(1, 0);
        hub.subscribe(2, 0);
        vm.stopPrank();
        vm.prank(slasher(1));
        hub.freeze(staker(1));
        skip(7 days - 1);
        vm.prank(slasher(2));
        hub.freeze(staker(1));
        skip(7 days - 1);
        vm.prank(slasher(1));
        vm.expectRevert("Already frozen by this service");
        hub.freeze(staker(1));
    }
}

contract LockerMock {
    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external {}
    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external {}
}

contract ServiceMock {
    function onSubscribe(address staker, uint256 lockingInUntil) external {}
}

contract SlasherMock {}
