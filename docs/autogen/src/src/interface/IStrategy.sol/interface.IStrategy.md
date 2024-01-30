# IStrategy
[Git Source](https://github.com/0xPolygon/staking-hub/blob/40ee450a1c3ec3de357aa9cf01be4ca37bff6da8/src/interface/IStrategy.sol)

**Author:**
Polygon Labs

A Strategy holds and manages Stakers' funds.

A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.


## Functions
### onRestake

*Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.*

*Triggered before `onRestake` on the Service.*


```solidity
function onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 amountOrId, uint8 maximumSlashingPercentage) external;
```

### onUnstake

*Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.*

*Triggered after `onUnstake` on the Service.*


```solidity
function onUnstake(address staker, uint256 service, uint256 amountOrId) external;
```

### onSlash

Takes a portion of a Staker's funds away.

*Called by the Hub when a Staker has been slashed by a Slasher of a Service that uses the Strategy.*


```solidity
function onSlash(address staker, uint256 service, uint256 amountOrId) external;
```

### balanceOf


```solidity
function balanceOf(address staker) external view returns (uint256);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The amount of funds the Staker has in the Strategy.|


