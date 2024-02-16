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
    event SubscriptionCanceled(address indexed staker, uint256 indexed serviceId);
    event Unsubscribed(address indexed staker, uint256 indexed serviceId);
    event InitiatedUnsubscribeWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event FinalizedUnsubscribeWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
    event SlasherUpdated(uint256 indexed serviceId, address indexed slasher);
    event StakerFrozen(address indexed staker, uint256 indexed serviceId, uint256 until);
    event StakerSlashed(address indexed staker, uint256 indexed serviceId, uint256 indexed lockerId, uint8 percentage, uint256 newBalance);

    /// @dev Called by locker.
    /// @dev Logs LockerRegistered.
    function registerLocker() external returns (uint256 id);

    /// @dev Called by service.
    /// @dev Logs ServiceRegistered.
    /// @dev Logs SlasherUpdated.
    function registerService(LockerSettings[] calldata lockers, uint40 unsubNotice, address slasher) external returns (uint256 id);

    /// @dev Called by staker.
    /// @dev Triggers onSubscribe on lockers.
    /// @dev Triggers onSubscribe on service.
    /// @dev Logs Subscribed.
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
