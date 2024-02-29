// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity 0.8.24;

interface IStakingHub {
    function serviceId(address serviceAddr) external view returns (uint256 id);
    function lockers(uint256 serviceId) external view returns (ILocker[] memory lockers);
}

interface ILocker {
    function totalSupplyAt(uint256 service, uint256 blockNumber) external view returns (uint256);
    function lastBalanceChange(address staker) external view returns (uint256 blockNumber);
    function balanceOf(address staker) external view returns (uint256 balance);
    function stakerPercentageAt(address staker, uint256 service, uint256 blockNumber) external view returns (uint256);
}

contract Rewards {
    struct RewardData {
        uint256 amount;
        uint256 historicalRPT;
    }

    IStakingHub internal immutable _hub;

    // full history
    mapping(uint256 service => mapping(uint256 epoch => mapping(ILocker locker => RewardData rewards))) internal _history;
    // all-time RPT
    mapping(uint256 service => mapping(ILocker locker => uint256 rewardPerToken)) internal _cumulativeRewardsPerToken;
    // claiming difference optimization
    mapping(address staker => mapping(uint256 service => uint256 epoch)) internal _stakerLastClaim;

    constructor(IStakingHub hub) {
        _hub = hub;
    }

    function distributeRewards(uint256[] memory amounts) external {
        uint256 service = _hub.serviceId(msg.sender);
        ILocker[] memory lockers = _hub.lockers(service);
        require(lockers.length == amounts.length, "Invalid amounts length");

        uint256 epoch = 0; // TODO (e.g. only allow for last epoch and disallow multiple)

        for (uint256 l; l < lockers.length; ++l) {
            // this is for efficient calc when balance hasn't changed_
            uint256 totalStaked = lockers[l].totalSupplyAt(service, _epochToBlock(epoch));
            if (totalStaked > 0) {
                _cumulativeRewardsPerToken[service][lockers[l]] += amounts[l] / totalStaked; // TODO Fix math
            }

            // this is for iterating when we can't calc efficiently because balance has been changing
            _history[service][epoch][lockers[l]].amount = amounts[l];
            _history[service][epoch][lockers[l]].historicalRPT = _cumulativeRewardsPerToken[service][lockers[l]];
        }
    }

    function claimRewards(address staker, uint256 service) external {
        uint256 epoch = 0; // TODO
        uint256 rewardPerToken = 0; // TODO
        _stakerLastClaim[staker][service] = epoch;
        uint256 amount = pendingRewards(staker, service);
        // TODO Transfer
    }

    function pendingRewards(address staker, uint256 service) public view returns (uint256 totalPendingRewards) {
        ILocker[] memory lockers = _hub.lockers(service);
        for (uint256 l = 0; l < lockers.length; ++l) {
            if (_blockToEpoch(lockers[l].lastBalanceChange(staker)) <= _stakerLastClaim[staker][service]) {
                // efficient
                uint256 cumulativeRPTNow = _cumulativeRewardsPerToken[service][lockers[l]];
                uint256 lastCumulativeRPT = _history[service][_stakerLastClaim[staker][service]][lockers[l]].historicalRPT;
                uint256 stakerBalance_ = lockers[l].balanceOf(staker);
                totalPendingRewards += stakerBalance_ * (cumulativeRPTNow - lastCumulativeRPT); // TODO Fix math
            } else {
                // iterative
                uint256 currentEpoch = 0; // TODO
                for (uint256 e = _stakerLastClaim[staker][service]; e < currentEpoch; ++e) {
                    totalPendingRewards += lockers[l].stakerPercentageAt(staker, service, _epochToBlock(e)) * _history[service][e][lockers[l]].amount; // TODO Fix math
                }
            }
        }
    }

    function _epochToBlock(uint256 epoch) internal view returns (uint256 blockNumber) {}
    function _blockToEpoch(uint256 blockNumber) internal view returns (uint256 epoch) {}
}
