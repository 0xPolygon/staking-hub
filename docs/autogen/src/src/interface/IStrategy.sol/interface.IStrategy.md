# IStrategy
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/interface/IStrategy.sol)

**Author:**
Polygon Labs

A Strategy holds and manages Stakers' funds.

A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.


## Functions
### deposit

Adds funds to be available to a Staker for restaking.

*Called by the Staker.*


```solidity
function deposit() external;
```

### withdraw

Retrieves [all/a partion of] Staker's funds from the Strategy.

The Staker must be unsubscribed from all Services first. // TODO: outdated

*Called by the Staker.*


```solidity
function withdraw(uint256 amount) external;
```

### onRestake

*Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.*

*Triggered before `onRestake` on the Service.*


```solidity
function onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage) external;
```

### onUnstake

*Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.*

*Triggered after `onUnstake` on the Service.*


```solidity
function onUnstake(address staker, uint256 service) external;
```

### onSlash

Takes a portion of a Staker's funds away.

*Called by the Hub when a Staker has been slashed by a Slasher of a Service that uses the Strategy.*


```solidity
function onSlash(address staker, uint8 percentage) external;
```

### balanceOf


```solidity
function balanceOf(address staker) external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of funds the Staker has in the Strategy.|


