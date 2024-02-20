// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct LockerSettings {
    uint256 lockerId;
    uint8 maxSlashPercentage;
}

/**
 * @title Staking Hub
 * @author Polygon Labs
 * @notice
 * Please see PRC-X for more details.
 */
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

    /**
     * @notice
     * Adds locker to hub. Must be contract.
     * @dev
     * Called by locker.
     * Logs `LockerRegistered`.
     * @return id Locker ID.
     */
    function registerLocker() external returns (uint256 id);

    /**
     * @notice
     * Adds service to hub. Must be contract.
     * @dev
     * Called by service.
     * Logs `ServiceRegistered`.
     * Logs `SlasherUpdated`.
     * @param lockers Settings for lockers. Must use 1-32 lockers. Must be ordered by locker ID. Max slash percentage cannot exceed `100`.
     * @param unsubNotice Wait period before unsubscription. Cannot be `0`. Prolongs slasher update timelock.
     * @param slasher Slashing contract. May be self.
     * @return id Service ID.
     */
    function registerService(LockerSettings[] calldata lockers, uint40 unsubNotice, address slasher) external returns (uint256 id);

    /**
     * @notice
     * Creates contractual agreement between staker and service. Reuses funds.
     * Cannot be used while frozen.
     * @dev
     * Called by staker.
     * Triggers `onSubscribe` on lockers.
     * Triggers `onSubscribe` on service.
     * Logs `Subscribed`.
     * @param service Service.
     * @param lockInUntil Promise to remain subscribed. May have effect on unsubscribing, slashing, etc.
     */
    function subscribe(uint256 service, uint40 lockInUntil) external;

    /**
     * @notice
     * Initiates ending of contractual agreement between staker and service.
     * Cannot be used while frozen.
     * @dev
     * Called by staker.
     * Triggers `onInitiateUnsubscribe` on service. Does not allow reverting if staker is not locked-in or slasher updated has been scheduled. Limits gas if staker is not locked-in.
     * May log `UnsubscriptionInitializationWarning`.
     * Logs `UnsubscriptionInitiated`.
     * @param service Service.
     * @return unsubscribableFrom Time when unsubscription can be finalized.
     */
    function initiateUnsubscribe(uint256 service) external returns (uint40 unsubscribableFrom);

    /**
     * @notice
     * Ends contractual agreement between staker and service. Must be inititated first.
     * Cannot be used while frozen.
     * @dev
     * Called by staker.
     * Triggers `onFinalizeUnsubscribe` on service. Does not allow reverting. Limits gas.
     * Triggers `onUnsubscribe` on lockers.
     * May log `UnsubscriptionFinalizationWarning`.
     * Logs `Unsubscribed`.
     * @param service Service.
     */
    function finalizeUnsubscribe(uint256 service) external;

    /**
     * @notice
     * Terminates contractual agreement between staker and service.
     * @dev
     * Called by service.
     * Triggers `onUnsubscribe` on lockers.
     * Logs `Unsubscribed`.
     * @param staker Staker.
     */
    function terminate(address staker) external;

    /**
     * @notice
     * Schedules slasher update.
     * @dev
     * Called by service.
     * Logs `SlasherUpdateInitiated`.
     * @param newSlasher New slasher. Cannot be `0`. May be self.
     * @return scheduledTime Time when slasher can be updated.
     */
    function initiateSlasherUpdate(address newSlasher) external returns (uint40 scheduledTime);

    /**
     * @notice
     * Updates slasher. Must be scheduled first.
     * @dev
     * Logs `SlasherUpdated`.
     */
    function finalizeSlasherUpdate() external;

    /**
     * @notice
     * Prevents staker from taking action. Starts or extends freeze period. Enables slashing.
     * Can be used once per freeze period.
     * @dev
     * Called by slasher.
     * Logs `StakerFrozen`.
     * @param staker Staker.
     */
    function freeze(address staker) external;

    /**
     * @notice
     * Punishes staker. Must be frozen by slasher first.
     * @dev
     * Called by slasher.
     * Triggers `onSlash` on lockers.
     * Logs `StakerSlashed`.
     * @param staker Staker.
     * @param percentages Percentage of funds to slash. Must specify for all lockers. Must be ordered by locker ID. Use `0` to skip locker. Sum for freeze period cannot exceed max slash percentage.
     */
    function slash(address staker, uint8[] calldata percentages) external;

    /**
     * @return Whether staker is frozen.
     */
    function isFrozen(address staker) external view returns (bool);
}
