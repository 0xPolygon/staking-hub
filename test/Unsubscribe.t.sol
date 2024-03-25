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

    uint40 LOCK_IN_PERIOD = 30 days;
    uint40 LOCK_UNTIL = uint40(vm.getBlockTimestamp()) + LOCK_IN_PERIOD;

    function setUp() public virtual {
        stakingHub = new StakingHub();
        msps.push(20);
        msps.push(20);
    }

    function test_initiateUnsubscribe() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        vm.expectEmit(true, true, true, false);
        emit IStakingHubEvents.UnsubscriptionInitiated(address(this), serviceId, LOCK_IN_PERIOD + 7 days + 1); // timestamp + unsubNotice
        stakingHub.initiateUnsubscribe(serviceId);
    }

    function test_initiateUnsubscribe_allowRevertWhenLockedIn() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        // note this is expecting a specific service impl
        // where the service reverts "onInitiateUnsubscribe" when locked in
        vm.expectRevert("Staker is locked in");
        stakingHub.initiateUnsubscribe(serviceId);

        // right at the end of the lock-in period, it still reverts
        vm.warp(LOCK_IN_PERIOD);
        vm.expectRevert();
        stakingHub.initiateUnsubscribe(serviceId);
    }

    function testFail_initiateUnsubscribe_NoWarningExpected_whenNotLockedIn() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        vm.expectEmit(true, true, false, false);
        emit IStakingHubEvents.UnsubscriptionInitializationWarning(address(this), serviceId, "0x");
        stakingHub.initiateUnsubscribe(serviceId);
    }

    function test_initiateUnsubscribe_notSubscribed() external {
        vm.expectRevert("Not subscribed");
        stakingHub.initiateUnsubscribe(0);
    }

    function test_initiateUnsubscribe_alreadyInitiated() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        stakingHub.initiateUnsubscribe(serviceId);

        vm.expectRevert("Unsubscription already initiated");
        stakingHub.initiateUnsubscribe(serviceId);
    }

    function test_initiateUnsubscribe_allowServiceRevertWhenNotLockedIn() external {
        MockServiceRevert service = new MockServiceRevert();
        uint256 id = service.init(stakingHub);

        stakingHub.subscribe(id, LOCK_UNTIL);

        // when not locked in, reverting service has no effect, but we see the warning event
        vm.warp(LOCK_IN_PERIOD + 1);
        vm.expectEmit(true, true, false, false);
        emit IStakingHubEvents.UnsubscriptionInitializationWarning(address(this), id, "0x");
        stakingHub.initiateUnsubscribe(id);
    }

    function test_initiateUnsubscribe_noLockInsDuringSlasherUpdate() external {
        // when a slasher update is scheduled, lock-ins are voided
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.expectRevert();
        stakingHub.initiateUnsubscribe(serviceId);

        services[0].initiateSlasherUpdate(address(1234));

        // now it should be allowed to unsubscribe even though we are still locked in
        stakingHub.initiateUnsubscribe(serviceId);

        vm.warp(7 days + 7 days + 1); // SLASHER_UPDATE_TIMELOCK + unsubNotice
        services[0].finalizeSlasherUpdate();

        // when slasher update was finalized, we should revert again as we are still locked in
        vm.expectRevert();
        stakingHub.initiateUnsubscribe(serviceId);
    }

    function test_initiateUnsubscribe_notifyLockers() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        stakingHub.initiateUnsubscribe(serviceId);

        uint256[] memory services_ = lockersOfService[serviceId][0].services(address(this));
        assertEq(services_.length, 0);

        services_ = lockersOfService[serviceId][1].services(address(this));
        assertEq(services_.length, 0);

        assertEq(lockersOfService[serviceId][0].isSubscribed(address(this), serviceId), false);
        assertEq(lockersOfService[serviceId][1].isSubscribed(address(this), serviceId), false);
    }

    function test_finalizeUnsubscribe() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        stakingHub.initiateUnsubscribe(serviceId);

        vm.warp(LOCK_IN_PERIOD + LOCK_UNTIL + 1);
        vm.expectEmit(true, true, false, false);
        emit IStakingHubEvents.Unsubscribed(address(this), serviceId);
        stakingHub.finalizeUnsubscribe(serviceId);
    }

    function test_finalizeUnsubscribe_cannotFinalizeWithoutInitiation() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.expectRevert("Unsubscription not initiated");
        stakingHub.finalizeUnsubscribe(0);
    }

    function test_finalizeUnsubscribe_unsubNoticeIsEnforced() external {
        uint256 serviceId = createLockersAndService(address(stakingHub), msps);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        vm.expectEmit(true, true, true, false);
        emit IStakingHubEvents.UnsubscriptionInitiated(address(this), serviceId, LOCK_IN_PERIOD + 7 days + 1);
        stakingHub.initiateUnsubscribe(serviceId);

        vm.expectRevert("Cannot finalize unsubscription yet");
        stakingHub.finalizeUnsubscribe(serviceId);
    }

    function test_finalizeUnsubscribe_allowServiceRevert() external {
        MockServiceRevert service = new MockServiceRevert();
        uint256 serviceId = service.init(stakingHub);
        stakingHub.subscribe(serviceId, LOCK_UNTIL);

        vm.warp(LOCK_IN_PERIOD + 1);
        stakingHub.initiateUnsubscribe(serviceId);

        vm.warp(LOCK_IN_PERIOD + LOCK_UNTIL + 1);
        vm.expectEmit(true, true, false, false);
        emit IStakingHubEvents.UnsubscriptionFinalizationWarning(address(this), serviceId, "0x");
        stakingHub.finalizeUnsubscribe(serviceId);
    }

    // finalize

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

contract MockServiceRevert {
    function init(StakingHub stakingHub) public returns (uint256 id) {
        ERC20LockerExample locker = new ERC20LockerExample(address(new ERC20Mock()), address(0));
        locker.initialize(address(stakingHub));
        uint256 lockerId = locker.registerLocker();
        LockerSettings[] memory settings = new LockerSettings[](1);
        settings[0] = LockerSettings(lockerId, 20);
        return stakingHub.registerService(settings, 7 days, address(123));
    }

    function onSubscribe(address staker, uint256 lockingInUntil) public {}

    function onInitiateUnsubscribe(address, /* staker */ bool /* lockedIn */ ) external pure {
        revert();
    }

    function onFinalizeUnsubscribe(address /* staker */ ) external pure {
        revert();
    }
}
