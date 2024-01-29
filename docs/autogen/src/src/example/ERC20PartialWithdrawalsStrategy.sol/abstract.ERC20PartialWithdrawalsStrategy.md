# ERC20PartialWithdrawalsStrategy
[Git Source](https://github.com/0xPolygon/staking-hub/blob/5b471248dcbc23982e535fe2d6ff7caddf0f0f98/src/example/ERC20PartialWithdrawalsStrategy.sol)

**Inherits:**
[BaseStrategy](/src/BaseStrategy.sol/abstract.BaseStrategy.md)

**Author:**
Polygon Labs

An ERC20-compatible abstract template contract inheriting from BaseStrategy

Enables partial withdrawals by tracking slashing risk


## State Variables
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
### constructor


```solidity
constructor(address _stakingHub) BaseStrategy(_stakingHub);
```

### _withdraw


```solidity
function _withdraw(uint256 amount) internal virtual;
```

### withdraw


```solidity
function withdraw(uint256 amount) external virtual;
```

### _withdrawableAmount

*returns amount of veTKN that can be withdrawn*


```solidity
function _withdrawableAmount() internal view returns (uint256 amount);
```

### _onRestake

*Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.*

*Triggered before `onRestake` on the Service.*


```solidity
function _onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage) internal override;
```

### _onUnstake

*Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.*

*Triggered after `onUnstake` on the Service.*


```solidity
function _onUnstake(address staker, uint256 service, uint256 amount) internal override;
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

