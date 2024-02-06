// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract StakingLayerStorage {
    // ========== PARAMETERS ==========

    // TODO: These are placeholders.
    uint256 internal constant SERVICE_UNSTAKE_GAS = 500_000;
    uint256 internal constant SLASHER_UPDATE_TIMELOCK = 7 days;
    uint256 internal constant STAKER_FREEZE_PERIOD = 7 days;

    // ========== EVENTS ==========

    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event RestakingError(uint256 indexed lockerId, address indexed staker, bytes data);
    event UnstakingParametersIgnored();
    event UnstakingError(uint256 indexed serviceOrLockerId, address indexed staker, bytes data); // Review: May need to change `serviceOrLockerId` to the address so they can be differentiated in case the IDs are the same.
    event StakerFrozen(address indexed staker, uint256 serviceId);
    event SlashingError(uint256 indexed lockerId, address indexed slasher, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
}