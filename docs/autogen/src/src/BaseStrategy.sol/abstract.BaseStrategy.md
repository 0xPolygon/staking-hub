# BaseStrategy
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/BaseStrategy.sol)

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


### slashableAmount

```solidity
mapping(address => uint256) slashableAmount;
```


### slashPercentages

```solidity
mapping(uint256 service => uint8) slashPercentages;
```


### services

```solidity
mapping(uint256 => Service) services;
```


### highestStakeService

```solidity
uint256 highestStakeService;
```


## Functions
### onlyStakingHub


```solidity
modifier onlyStakingHub();
```

### constructor


```solidity
constructor(address _stakingHub);
```

### _balanceOf


```solidity
function _balanceOf(address staker) internal view virtual returns (uint256);
```

### _withdraw


```solidity
function _withdraw(uint256 amount) internal virtual;
```

### deposit


```solidity
function deposit() external virtual;
```

### onSlash


```solidity
function onSlash(address user, uint8 percentage) external virtual;
```

### withdraw


```solidity
function withdraw(uint256 amount) external;
```

### balanceOf


```solidity
function balanceOf(address staker) external view returns (uint256);
```

### _withdrawableAmount

*returns amount of veTKN that can be withdrawn*


```solidity
function _withdrawableAmount() private view returns (uint256 amount);
```

### onRestake

*Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.*

*Triggered before `onRestake` on the Service.*


```solidity
function onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage)
    external
    override
    onlyStakingHub;
```

### onUnstake

*Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.*

*Triggered after `onUnstake` on the Service.*


```solidity
function onUnstake(address staker, uint256 service) external override onlyStakingHub;
```

### updateHighestStake


```solidity
function updateHighestStake(uint256 service, uint256 totalStakedAmount) private;
```

## Structs
### Service

```solidity
struct Service {
    uint256 index;
    uint256 left;
    uint256 right;
    uint256 amount;
}
```

