// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC20Mock} from "../lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ERC20LockerExample} from "../src/example/ERC20LockerExample.sol";
import {ERC20Locker} from "../src/template/ERC20Locker.sol";
import {StakingHub} from "../src/StakingHub.sol";
import {LockerSettings} from "../src/interface/IStakingHub.sol";
import {ServicePoS} from "../src/example/ServicePoS.sol";
import {IStakingHubEvents} from "../src/interface/IStakingHub.sol";

contract Subscribe is Test {
    StakingHub stakingHub;
    mapping(uint256 => ERC20Locker[]) lockersOfService;
    mapping(uint256 => LockerSettings[]) settingsOfService;
    ServicePoS[] services;

    LockerSettings[] settings;
    ERC20Locker[] lockers;
    uint8[] msps;

    uint40 LOCK_UNTIL = uint40(vm.getBlockTimestamp()) + 30 days;

    function setUp() public virtual {
        stakingHub = new StakingHub();
    }

    function test_subscribe() external {
        msps.push(20);
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);

        vm.expectEmit(true, true, true, false);
        emit IStakingHubEvents.Subscribed(address(this), serviceId, LOCK_UNTIL);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        // test freeze to see if staker is subscribed
        services[0].freeze(address(this), "0x");
    }

    function test_subscribe_invalidService() external {
        msps.push(20);
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);

        vm.expectRevert("Invalid service");
        stakingHub.subscribe(serviceId + 1, LOCK_UNTIL);
    }

    function test_subscribe_alreadySubscribed() external {
        msps.push(20);
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);

        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.expectRevert("Already subscribed");
        stakingHub.subscribe(serviceId, LOCK_UNTIL);
    }

    // locker onSubscribe
    function test_onSubscribe_unauthorized() external {
        msps.push(20);
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);

        vm.expectRevert("Unauthorized");
        lockersOfService[serviceId][0].onSubscribe(address(0), serviceId, 20);
    }

    function test_onSubscribe_multipleLockers() external {
        msps.push(20);
        msps.push(50);
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);

        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        uint256[] memory services_ = lockersOfService[serviceId][0].services(address(this));
        assertEq(services_.length, 1);
        assertEq(services_[0], serviceId);

        services_ = lockersOfService[serviceId][1].services(address(this));
        assertEq(services_.length, 1);
        assertEq(services_[0], serviceId);

        assertEq(true, lockersOfService[serviceId][0].isSubscribed(address(this), serviceId));
        assertEq(true, lockersOfService[serviceId][1].isSubscribed(address(this), serviceId));
    }

    function test_onSubscribe_multipleServices_sameLockers() external {
        msps.push(20);
        msps.push(20);
        uint256 serviceId1 = createLockersAndService(address(stakingHub), msps);
        uint256 serviceId2 = copyService(address(stakingHub), serviceId1);

        stakingHub.subscribe(serviceId1, LOCK_UNTIL);
        stakingHub.subscribe(serviceId2, LOCK_UNTIL);

        // locker 0
        uint256[] memory services_ = lockersOfService[serviceId1][0].services(address(this));
        assertEq(services_.length, 2);
        assertEq(services_[0], serviceId1);
        assertEq(services_[1], serviceId2);

        // locker 1
        services_ = lockersOfService[serviceId1][1].services(address(this));
        assertEq(services_.length, 2);
        assertEq(services_[0], serviceId1);
        assertEq(services_[1], serviceId2);
    }

    function test_onSubscribe_on_service() external {
        msps.push(20);
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);

        vm.expectEmit(true, true, false, false);
        emit ServicePoS.ChecksPassed(address(this), LOCK_UNTIL);

        stakingHub.subscribe(serviceId, LOCK_UNTIL);
    }

    // ***
    // HELPERS
    // ***

    function createLockersAndService(address stakingHub_, uint8[] memory maxSlashPercentages_) internal returns (uint256 serviceId) {
        for (uint256 i; i < maxSlashPercentages_.length; ++i) {
            ERC20LockerExample locker = new ERC20LockerExample(address(new ERC20Mock()), address(0));
            locker.initialize(stakingHub_);
            uint256 id = locker.registerLocker();
            lockers.push(locker);
            settings.push(LockerSettings(id, maxSlashPercentages_[i]));
        }

        ServicePoS service = new ServicePoS(stakingHub_, lockers);
        service.init(settings, 7 days /* unsubNotice */ );
        services.push(service);

        lockersOfService[service.id()] = lockers;
        settingsOfService[service.id()] = settings;

        lockers = new ERC20Locker[](0);
        settings = new LockerSettings[](0);

        return service.id();
    }

    function copyService(address stakingHub_, uint256 serviceToCopy) internal returns (uint256 serviceId) {
        ServicePoS service = new ServicePoS(stakingHub_, lockersOfService[serviceToCopy]);
        service.init(settingsOfService[serviceToCopy], 7 days /* unsubNotice */ );
        services.push(service);
        lockersOfService[service.id()] = lockersOfService[serviceToCopy];
        settingsOfService[service.id()] = settingsOfService[serviceToCopy];

        return service.id();
    }
}
