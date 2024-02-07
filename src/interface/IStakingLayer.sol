// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

interface IStakingLayer {
    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event Restaked(address indexed staker, uint256 indexed serviceId, uint40 commitUntil);
    event UnstakingInitiated(address indexed staker, uint256 indexed serviceId);
    event Unstaked(address indexed staker, uint256 indexed serviceId);
    event UnstakingError(uint256 indexed serviceOrLockerId, address indexed staker, bytes data); // Review: May need to change `serviceOrLockerId` to the address so they can be differentiated in case the IDs are the same.
    event StakerFrozen(address indexed staker, uint256 serviceId);
    event SlashingError(uint256 indexed lockerId, address indexed slasher, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
    event SlasherUpdateFinalized(uint256 indexed serviceId);
}
