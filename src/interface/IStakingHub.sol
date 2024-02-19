// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct LockerSettings {
    uint256 lockerId;
    uint8 maxSlashPercentage;
}

interface IStakingHub {
    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event Subscribed(address indexed staker, uint256 indexed serviceId, uint40 lockInUntil);
    event UnsubscriptionInitiated(address indexed staker, uint256 indexed serviceId);
    event Unsubscribed(address indexed staker, uint256 indexed serviceId);
    event UnsubscriptionInitializationWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event UnsubscriptionFinalizationWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
    event SlasherUpdated(uint256 indexed serviceId, address indexed slasher);
    event StakerFrozen(address indexed staker, uint256 indexed serviceId, uint256 until);
    event StakerSlashed(address indexed staker, uint256 indexed serviceId, uint256[] lockerIds, uint8[] percentages);

    function registerLocker() external returns (uint256 id);

    function registerService(LockerSettings[] calldata lockers, uint40 unsubNotice, address slasher) external returns (uint256 id);

    function subscribe(uint256 service, uint40 lockInUntil) external;

    function initiateUnsubscribe(uint256 service) external returns (uint40 unsubscribableFrom);

    function finalizeUnsubscribe(uint256 service) external;

    function terminate(address staker) external;

    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime);

    function finalizeSlasherUpdate() external;

    function freeze(address staker) external;

    function slash(address staker, uint8[] calldata percentages) external;

    function isFrozen(address staker) external view returns (bool);
}
