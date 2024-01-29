# SubscriptionsStd
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/lib/SubscriptionsStd.sol)

A library for managing `Subscriptions`.

How subscriptions work:

- Upon a subscription, there may be a lock-in period required by the Service the Staker is subscribing to.

- The subscription remains active until the Staker unsubscribes through the Hub.

*Do not modify `Subscriptions` manually. Always use `SubscriptionsStd` for reading from and writing to `Subscriptions`.*


## Functions
### track

Starts tracking a new subscription, or updates the lock-in period of the subscription that is already being tracked.


```solidity
function track(Subscriptions storage list, uint256 service, uint256 lockInUntil) public;
```

### stopTracking

Stops tracking a subscription.


```solidity
function stopTracking(Subscriptions storage list, uint256 service) public;
```

### freeze

Sets the end of the freeze period of a subscription that is already being tracked.


```solidity
function freeze(Subscriptions storage list, uint256 service, uint256 newFreezeEnd) public;
```

### unfreeze

Resets the end of the freeze period of a subscription that is already being tracked.


```solidity
function unfreeze(Subscriptions storage list, uint256 service) public;
```

### isActive


```solidity
function isActive(Subscriptions storage list, uint256 service) public view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether a subscription is active.|


### isLockedIn


```solidity
function isLockedIn(Subscriptions storage list, uint256 service) public view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether a subscription is active.|


### isFrozen


```solidity
function isFrozen(Subscriptions storage list, uint256 service) public view returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the Staker is frozen.|


### getUnlock


```solidity
function getUnlock(Subscriptions storage list, uint256 service) public view returns (uint256);
```

### iterate

*Use to get the next subscription from the linked list.*


```solidity
function iterate(Subscriptions storage list, uint256 service) public view returns (uint256);
```

## Structs
### Item

```solidity
struct Item {
    bool active;
    uint256 lockedInUntil;
    uint256 lastFreezeEnd;
    uint256 next;
}
```

