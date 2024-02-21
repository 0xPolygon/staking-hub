// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

struct LockerSettings {
    uint256 lockerId;
    uint8 maxSlashPercentage;
}

/// @title Staking Hub
/// @author Polygon Labs
/// @notice Please see PRC-X for more details.
interface IStakingHub {
    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event Subscribed(address indexed staker, uint256 indexed serviceId, uint40 lockInUntil);
    event UnsubscriptionInitializationWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event UnsubscriptionInitiated(address indexed staker, uint256 indexed serviceId);
    event UnsubscriptionFinalizationWarning(uint256 indexed serviceId, address indexed staker, bytes data);
    event Unsubscribed(address indexed staker, uint256 indexed serviceId);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
    event SlasherUpdated(uint256 indexed serviceId, address indexed slasher);
    event StakerFrozen(address indexed staker, uint256 indexed serviceId, uint256 until);
    event StakerSlashed(address indexed staker, uint256 indexed serviceId, uint256[] lockerIds, uint8[] percentages);

    /// @notice Adds locker to hub. Must be contract.
    /// @dev Called by locker.
    /// @dev Logs `LockerRegistered`.
    /// @return id Locker ID.
    function registerLocker() external returns (uint256 id);

    /// @notice Adds service to hub. Must be contract.
    /// @dev Called by service.
    /// @dev Logs `ServiceRegistered`.
    /// @dev Logs `SlasherUpdated`.
    /// @param lockers Settings for lockers. Must use 1-32 lockers. Must be ordered by locker ID. Max slash percentage cannot exceed `100`.
    /// @param unsubNotice Wait period before unsubscription. Cannot be `0`. Prolongs slasher update timelock.
    /// @param slasher Slashing contract. May be self.
    /// @return id Service ID.
    function registerService(LockerSettings[] calldata lockers, uint40 unsubNotice, address slasher) external returns (uint256 id);

    /// @notice Creates contractual agreement between staker and service. Reuses funds.
    /// @notice Cannot be used while frozen.
    /// @dev Called by staker.
    /// @dev Triggers `onSubscribe` on lockers.
    /// @dev Triggers `onSubscribe` on service.
    /// @dev Logs `Subscribed`.
    /// @param service Service.
    /// @param lockInUntil Promise to remain subscribed. May have effect on unsubscribing, slashing, etc.
    function subscribe(uint256 service, uint40 lockInUntil) external;

    /// @notice Initiates ending of contractual agreement between staker and service.
    /// @notice Cannot be used while frozen.
    /// @dev Called by staker.
    /// @dev Triggers `onInitiateUnsubscribe` on service. Does not allow reverting if staker is not locked-in or slasher updated has been scheduled. Limits gas if staker is not locked-in.
    /// @dev May log `UnsubscriptionInitializationWarning`.
    /// @dev Logs `UnsubscriptionInitiated`.
    /// @param service Service.
    /// @return unsubscribableFrom Time when unsubscription can be finalized.
    function initiateUnsubscribe(uint256 service) external returns (uint40 unsubscribableFrom);

    /// @notice Ends contractual agreement between staker and service. Must be inititated first.
    /// @notice Cannot be used while frozen.
    /// @dev Called by staker.
    /// @dev Triggers `onFinalizeUnsubscribe` on service. Does not allow reverting. Limits gas.
    /// @dev Triggers `onUnsubscribe` on lockers.
    /// @dev May log `UnsubscriptionFinalizationWarning`.
    /// @dev Logs `Unsubscribed`.
    /// @param service Service.
    function finalizeUnsubscribe(uint256 service) external;

    /// @notice Terminates contractual agreement between staker and service.
    /// @dev Called by service.
    /// @dev Triggers `onUnsubscribe` on lockers.
    /// @dev Logs `Unsubscribed`.
    /// @param staker Staker.
    function terminate(address staker) external;

    /// @notice Schedules slasher update.
    /// @dev Called by service.
    /// @dev Logs `SlasherUpdateInitiated`.
    /// @param newSlasher New slasher. Cannot be `0`. May be self.
    /// @return scheduledTime Time when slasher can be updated.
    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime);

    /// @notice Updates slasher. Must be scheduled first.
    /// @dev Logs `SlasherUpdated`.
    function finalizeSlasherUpdate() external;

    /// @notice Prevents staker from taking action. Starts or extends freeze period. Enables slashing.
    /// @notice Can be used once per freeze period.
    /// @dev Called by slasher.
    /// @dev Logs `StakerFrozen`.
    /// @param staker Staker.
    function freeze(address staker) external;

    /// @notice Punishes staker. Must be frozen by slasher first.
    /// @dev Called by slasher.
    /// @dev Triggers `onSlash` on lockers.
    /// @dev Logs `StakerSlashed`.
    /// @param staker Staker.
    /// @param percentages Percentage of funds to slash. Must specify for all lockers. Must be ordered by locker ID. Use `0` to skip locker. Sum for freeze period cannot exceed max slash percentage.
    function slash(address staker, uint8[] calldata percentages) external;

    /// @return Whether staker is frozen.
    function isFrozen(address staker) external view returns (bool);
}
