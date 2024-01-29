# IService
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/interface/IService.sol)

**Author:**
Polygon Labs

A Service represents a network.

Stakers can subscribe to the Service (i.e., restake).


## Functions
### onSubscribe

Lets a Staker restake with the Service.

Performs all neccessary checks on the Staker (e.g., voting power, whitelist, BLS-key, etc.).

*Called by the Hub when a Staker subscribes to the Service.*

*The Service can revert.*


```solidity
function onSubscribe(address staker, uint256 stakedUntil) external;
```

### onUnsubscribe

Lets a Staker unstake from the Service.

Performs all neccessary checks on the Staker.

*Called by the Hub when a Staker unsubscribes from the Service.*

*The Service can revert when the subscription hasn't expired.*


```solidity
function onUnsubscribe(address staker) external;
```

### onFreeze

Functionality not defined.

*Called by the Hub when a Staker has been frozen by a Slasher of the Service.*


```solidity
function onFreeze(address staker) external;
```

