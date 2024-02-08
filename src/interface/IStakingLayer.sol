// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.24;

struct SlashingInput {
    uint256 lockerId;
    uint8 percentage;
}

interface IStakingLayer {
    event LockerRegistered(address indexed locker, uint256 indexed lockerId);
    event ServiceRegistered(address indexed service, uint256 indexed serviceId);
    event Restaked(address indexed staker, uint256 indexed serviceId, uint40 commitUntil);
    event UnstakingInitiated(address indexed staker, uint256 indexed serviceId);
    event Unstaked(address indexed staker, uint256 indexed serviceId);
    event UnstakingInitiatedError(uint256 indexed serviceId, address indexed staker, bytes data);
    event UnstakingError(uint256 indexed serviceId, address indexed staker, bytes data);
    event SlasherUpdateInitiated(uint256 indexed serviceId, address indexed newSlasher);
    event SlasherUpdated(uint256 indexed serviceId, address indexed slasher);
    event StakerFrozen(address indexed staker, uint256 indexed serviceId, uint40 until);
    event StakerSlashed(address indexed staker, uint256 indexed serviceId, uint256 indexed lockerId, uint8 percentage);
}
