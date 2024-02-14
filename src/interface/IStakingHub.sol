// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct LockerSettings {
    uint256 lockerId;
    uint8 maxSlashPercentage;
    uint256 minAmount;
}

interface IStakingHub {
    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event Subscribed(address indexed staker, uint256 indexed serviceId, uint40 lockInUntil);
    event SubscriptionCanceled(address indexed staker, uint256 indexed serviceId);
    event Unsubscribed(address indexed staker, uint256 indexed serviceId);
    event SubscriptionCancelationWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event UnsubscriptionWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
    event SlasherUpdated(uint256 indexed serviceId, address indexed slasher);
    event StakerFrozen(address indexed staker, uint256 indexed serviceId, uint256 until);
    event StakerSlashed(address indexed staker, uint256 indexed serviceId, uint256 indexed lockerId, uint8 percentage, uint256 newBalance);
    event SlashedStakeBurned(uint256 indexed lockerId, address indexed staker);
}
