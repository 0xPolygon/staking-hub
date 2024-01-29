# BaseStrategy
[Git Source](https://github.com/0xPolygon/staking-hub/blob/5b471248dcbc23982e535fe2d6ff7caddf0f0f98/src/BaseStrategy.sol)

**Inherits:**
[IStrategy](/src/interface/IStrategy.sol/interface.IStrategy.md)

**Author:**
Polygon Labs

A Strategy holds and manages Stakers' funds.

A Staker deposits funds into the Strategy before subscribing to a Services that uses the Strategy.


## State Variables
### stakingHub

```solidity
address public stakingHub;
```


### totalSupplies

```solidity
mapping(uint256 => uint256) totalSupplies;
```


## Functions
### constructor


```solidity
constructor(address _stakingHub);
```

### balanceOf


```solidity
function balanceOf(address staker) public view virtual returns (uint256);
```

### _onSlash


```solidity
function _onSlash(address user, uint256 service, uint256 amount) internal virtual;
```

### _onRestake


```solidity
function _onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage) internal virtual;
```

### _onUnstake


```solidity
function _onUnstake(address staker, uint256 service, uint256 amount) internal virtual;
```

### onSlash

*Triggered by the Hub when a staker gets slashed on penalized*


```solidity
function onSlash(address user, uint256 service, uint256 amount) external;
```

### onRestake

*Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.*

*Triggered before `onRestake` on the Service.*


```solidity
function onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 amount, uint8 maximumSlashingPercentage) external override;
```

### onUnstake

*Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.*

*Triggered after `onUnstake` on the Service.*


```solidity
function onUnstake(address staker, uint256 service, uint256 amount) external override;
```

## Events
### Staked

```solidity
event Staked(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage);
```

### Unstaked

```solidity
event Unstaked(address staker, uint256 service);
```

### Slashed

```solidity
event Slashed(address staker, uint8 percentage);
```

