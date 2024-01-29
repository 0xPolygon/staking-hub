# Subscriptions
[Git Source](https://github.com/0xPolygon/staking-hub/blob/e29d25293d7b9a1ba3138152afe6282a955a9d28/src/lib/SubscriptionsStd.sol)

*The single-linked list data-type for tracking subscriptions.*


```solidity
struct Subscriptions {
    uint256 head;
    mapping(uint256 => SubscriptionsStd.Item) items;
}
```

