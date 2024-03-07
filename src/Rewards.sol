// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

interface IStakingHub {
    function serviceId(address serviceAddr) external view returns (uint256 id);
    function lockers(uint256 serviceId) external view returns (ILocker[] memory lockers);
}

interface ILocker {
    function totalStakeAt(uint256 service, uint256 blockNumber) external view returns (uint256 totalStake);
    // The first element is a special element that tell the balance the staker had in the epoch they claimed for last.
    // Any other elements return stakes for blocks when the stake changed, closest to the epoch beginnings (snapshots). This can be calculated as `lastClaimedEpochBlock + epochLength * n`. Up to the current epoch.
    function getStakeChanges(address staker, uint256 service, uint256 lastClaimedEpochBlock, uint256 epochLength)
        external
        view
        returns (uint256[] memory blocks, uint256[] memory stakes);
}

// TODO Reentrancy guard
contract Rewards {
    struct Distribution {
        bool distributed;
        mapping(ILocker locker => uint256) cumulativeRPT;
    }

    IStakingHub internal immutable _hub;

    mapping(uint256 service => mapping(uint256 epoch => Distribution)) internal _history;
    mapping(address staker => mapping(uint256 service => uint256 epoch)) internal _stakerClaimedThrough;

    constructor(IStakingHub hub) {
        _hub = hub;
    }

    function distributeRewards(uint256[] memory amounts) external {
        uint256 service = _hub.serviceId(msg.sender);
        ILocker[] memory lockers = _hub.lockers(service);
        require(lockers.length == amounts.length, "Invalid amounts length");
        uint256 epoch = _currentEpoch(service) - 1;
        require(!_history[service][epoch].distributed, "Already distributed");
        _history[service][epoch].distributed = true;
        for (uint256 l; l < lockers.length; ++l) {
            uint256 totalStaked = lockers[l].totalStakeAt(service, _epochToBlock(epoch));
            if (totalStaked > 0) {
                _history[service][epoch].cumulativeRPT[lockers[l]] = amounts[l] / totalStaked; // TODO Solidity math
            }
            // TODO Transfer
        }
    }

    function pendingRewards(address staker, uint256 service) public view returns (uint256 total) {
        ILocker[] memory lockers = _hub.lockers(service);
        for (uint256 l = 0; l < lockers.length; ++l) {
            total += _pendingPerLocker(staker, service, lockers[l]);
        }
    }

    function claimRewards(address staker, uint256 service) external {
        uint256 amount = pendingRewards(staker, service);
        _stakerClaimedThrough[staker][service] = _currentEpoch(service) - 1;
        amount; // TODO Transfer
    }

    function _pendingPerLocker(address staker, uint256 service, ILocker locker) internal view returns (uint256 rewardTokens) {
        uint256 currentEpoch = _currentEpoch(service);
        uint256 lastClaimedEpoch = _stakerClaimedThrough[staker][service];
        (uint256[] memory blocks, uint256[] memory stakes) =
            locker.getStakeChanges(staker, service, _stakerClaimedThrough[staker][service], _epochLength(service));
        if (blocks.length != 1) {
            for (uint256 b = 1; b < blocks.length; ++b) {
                uint256 lastCumulativeRPT = _history[service][lastClaimedEpoch].cumulativeRPT[locker];
                uint256 balanceDifferentForEpoch = _blockToEpoch(blocks[b]);
                uint256 claimableCumulativeRPT = _history[service][balanceDifferentForEpoch - 1].cumulativeRPT[locker] - lastCumulativeRPT;
                rewardTokens += claimableCumulativeRPT * stakes[b - 1];
                lastClaimedEpoch = balanceDifferentForEpoch - 1;
                if (lastClaimedEpoch == currentEpoch) return (rewardTokens);
            }
        }
        uint256 finalClaimableCumulativeRPT =
            _history[service][currentEpoch - 1].cumulativeRPT[locker] - _history[service][lastClaimedEpoch].cumulativeRPT[locker];
        rewardTokens += finalClaimableCumulativeRPT * stakes[blocks.length - 1];
    }

    function _currentEpoch(uint256 service) internal view returns (uint256 epoch) {
        // TODO
    }

    function _epochLength(uint256 service) internal view returns (uint256 length) {
        // TODO
    }

    function _epochToBlock(uint256 epoch) internal view returns (uint256 blockNumber) {
        // TODO
    }

    function _blockToEpoch(uint256 blockNumber) internal view returns (uint256 epoch) {
        // TODO
    }
}
