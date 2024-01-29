# Hub
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/StakingHub.sol)

**Author:**
Polygon Labs

The Hub is a permissionless place where Stakers and Services gather.

The goal is to create new income streams for Stakers. Meanwhile, Services can acquire Stakers.

Stakers can subscribe to Services (i.e., restake) via Strategies.


## State Variables
### SLASHER_UPDATE_TIMELOCK

```solidity
uint256 private constant SLASHER_UPDATE_TIMELOCK = 7 days;
```


### STAKER_FREEZE_PERIOD

```solidity
uint256 private constant STAKER_FREEZE_PERIOD = 7 days;
```


### _strategyCounter

```solidity
uint256 private _strategyCounter;
```


### _serviceCounter

```solidity
uint256 private _serviceCounter;
```


### strategies

```solidity
mapping(address strategy => uint256 strategyId) public strategies;
```


### services

```solidity
mapping(address service => uint256 serviceId) public services;
```


### serviceData

```solidity
mapping(uint256 serviceId => ServiceData serviceData) public serviceData;
```


### slasherUpdate

```solidity
mapping(uint256 serviceId => SlasherUpdate slasherUpdate) public slasherUpdate;
```


### strategyData

```solidity
mapping(uint256 strategyId => StrategyData strategyData) public strategyData;
```


### subscriptions

```solidity
mapping(address staker => Subscriptions subscriptions) public subscriptions;
```


## Functions
### registerStrategy

Adds a new Strategy to the Hub.

*Called by the Strategy.*


```solidity
function registerStrategy() external returns (uint256 id);
```

### registerService

Adds a new Service to the Hub.

*Called by the Service.*


```solidity
function registerService(uint256[] calldata strategies_, SlashingInput[] calldata maximumSlashingPercentages, address slasher) external returns (uint256 id);
```

### restake

Subscribes a Staker to a Service.

Extends the lock-in period if the Staker is already subscribed to the Service.

By restaking, the Staker subscribes to the Service, subject to that Service's contract logic.

*Called by the Staker.*

*Calls `onSubscribe` on all Strategies the Service uses.*

*Calls `onSubscribe` on the Service.*


```solidity
function restake(uint256 serviceId, uint256 lockInUntil) external;
```

### unstake

Unsubscribes a Staker from a Service.

Let's the Staker unsubscribe immediately if the Service has scheduled a Slasher update.

By unstaking completely, the Staker unsubscribes from the Service, subject to that Service's contract logic.

*Called by the Staker.*

*Calls `onSubscribe` on the Service.*

*Calls `onSubscribe` on all Strategies the Service uses.*


```solidity
function unstake(uint256 serviceId) external;
```

### initiateSlasherUpdate

Schedule a Slasher update for a Service.

*Called by the Service.*


```solidity
function initiateSlasherUpdate(address newSlasher) external returns (uint256 scheduledTime);
```

### finalizeSlasherUpdate

Apply a scheduled Slasher update for a Service.

*Called by anyone.*


```solidity
function finalizeSlasherUpdate() external;
```

### onFreeze

Temporarily prevents a Staker from unsubscribing from a Service.

This period can be used to prove the Staker should be slashed.

*Called by a Slasher of the Service.*


```solidity
function onFreeze(uint256 serviceId, address staker) external;
```

### onSlash

Takes a portion of a Staker's funds away.

The Staker must be frozen first.

*Called by a Slasher of a Service.*

*Calls onSlash on all Strategies the Services uses.*


```solidity
function onSlash(uint256 serviceId, address staker, SlashingInput[] calldata percentages) external;
```

### hasActiveSubscriptions


```solidity
function hasActiveSubscriptions(address staker) external view returns (bool);
```

## Events
### StrategyRegistered

```solidity
event StrategyRegistered(address indexed strategy, uint256 indexed strategyId);
```

### ServiceRegistered

```solidity
event ServiceRegistered(address indexed service, uint256 indexed serviceId);
```

### SlasherUpdateInitiated

```solidity
event SlasherUpdateInitiated(uint256 indexed serviceId, address newSlasher);
```

## Structs
### ServiceData

```solidity
struct ServiceData {
    IService service;
    uint256[] strategies;
    mapping(uint256 strategyId => uint256 percentage) maximumSlashingPercentages;
    address slasher;
}
```

### SlasherUpdate

```solidity
struct SlasherUpdate {
    address newSlasher;
    uint256 scheduledTime;
}
```

### StrategyData

```solidity
struct StrategyData {
    IStrategy strategy;
    uint256[] services;
}
```

### SlashingInput

```solidity
struct SlashingInput {
    uint256 strategyId;
    uint256 percentage;
}
```

