# ISlasherExample
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/example/ISlasher.sol)

**Author:**
Polygon Labs

A Slasher separates the freezing and slashing functionality from a Service.


## Functions
### freeze

Temporarily prevents a Staker from taking action.

This period can be used to prove the Staker should be slashed.

*Called by [up to the Slasher to decide].*

*Calls onFreeze on the Hub.*


```solidity
function freeze(address staker, bytes calldata proof) external;
```

### slash

Takes a portion of a Staker's funds away.

The Staker must be frozen first.

*Called by [up to the Slasher to decide].*

*Calls onSlash on the Hub.*


```solidity
function slash(address staker, uint256 percentage) external;
```

