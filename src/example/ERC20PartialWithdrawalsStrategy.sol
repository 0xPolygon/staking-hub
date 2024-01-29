// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {BaseStrategy} from "../BaseStrategy.sol";

/// @title ERC20PartialWithdrawalsStrategy
/// @author Polygon Labs
/// @notice An ERC20-compatible abstract template contract inheriting from BaseStrategy
/// @notice Enables partial withdrawals by tracking slashing risk
abstract contract ERC20PartialWithdrawalsStrategy is BaseStrategy {
    // TODO add tracking onSlash?

    mapping(address => uint256) slashableAmount;
    mapping(uint256 service => uint8) slashPercentages;
    mapping(uint256 => Service) services;
    uint256 highestStakeService;

    struct Service {
        uint256 index;
        uint256 left;
        uint256 right;
        uint256 amount;
    }

    constructor(address _stakingHub) BaseStrategy(_stakingHub) {}

    // FUNCTIONS TO IMPLEMENT
    // more in BaseStrategy
    function _withdraw(uint256 amount) internal virtual;

    function withdraw(uint256 amount) external virtual {
        require(_withdrawableAmount() >= amount, "BaseStrategy: amount exceeds withdrawable amount");
        _withdraw(amount);
    }

    /// @dev returns amount of veTKN that can be withdrawn
    function _withdrawableAmount() internal view returns (uint256 amount) {
        uint256 slashable = slashableAmount[msg.sender];
        uint256 highestStake = services[highestStakeService].amount;

        // use highest
        return balanceOf(msg.sender) - highestStake >= slashable ? highestStake : slashable;
    }

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Strategy.
    /// @dev Triggered before `onRestake` on the Service.
    function _onRestake(
        address staker,
        uint256 service,
        uint256 lockingInUntil, // review not required here, keep it?
        uint256 stakingAmount,
        uint8 maximumSlashingPercentage
    ) internal override {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        uint256 totalStakedAmount = services[service].amount;

        if (slashPercentages[service] == 0) {
            slashPercentages[service] = maximumSlashingPercentage;
            slashableAmount[staker] += ((stakingAmount / balanceOf(staker)) * maximumSlashingPercentage) / 100;
        } else if (slashPercentages[service] == maximumSlashingPercentage) {
            slashableAmount[staker] += ((stakingAmount / balanceOf(staker)) * maximumSlashingPercentage) / 100;
        } else {
            // new maximumSlashingPercentage
            // update slashablePercentage using the new maximumSlashingPercentage
            uint256 oldSlash = ((totalStakedAmount - stakingAmount) * slashPercentages[service]) / 100;
            uint256 newSlash = ((totalStakedAmount) * maximumSlashingPercentage) / 100;
            slashableAmount[staker] -= oldSlash;
            slashableAmount[staker] += newSlash;
        }

        updateHighestStake(service, totalStakedAmount);

        require(slashableAmount[staker] <= balanceOf(staker), "BaseStrategy: Slashable amount too high.");
    }

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Strategy.
    /// @dev Triggered after `onUnstake` on the Service.
    function _onUnstake(address staker, uint256 service, uint256 amount) internal override {
        require(msg.sender == stakingHub, "Only StakingHub can call this function.");

        // review only allow unstaking the same amount that you staked before.
        // we can avoid loops in the onUnstake hook this way!

        uint256 slashChange = services[service].amount * slashPercentages[service] / 10_000;

        slashableAmount[staker] -= slashChange;

        // delete service entry
        Service memory serviceEntry = services[service];
        services[serviceEntry.left].right = serviceEntry.right;
        services[serviceEntry.right].left = serviceEntry.left;
        delete services[service];

        // update highestStakeService if necessary
        if (service == highestStakeService) {
            highestStakeService = serviceEntry.left;
        }
    }

    function updateHighestStake(uint256 service, uint256 totalStakedAmount) private {
        // new high, if first entry, second line won't have any effect
        if (services[highestStakeService].amount <= totalStakedAmount) {
            services[service] = Service({index: service, left: highestStakeService, right: 0, amount: totalStakedAmount});
            services[highestStakeService].right = service;
            highestStakeService = service;
        } else {
            // sort it in
            uint256 currentServiceIndex = services[highestStakeService].left;
            while (true) {
                Service memory currentService = services[currentServiceIndex];

                // found lower entry
                if (currentService.amount < totalStakedAmount) {
                    Service memory higherService = services[currentService.right];
                    services[service] = Service({index: service, left: currentService.index, right: higherService.index, amount: totalStakedAmount});
                    higherService.left = service;
                    currentService.right = service;
                    break;
                }

                // found bottom
                if (currentService.amount > totalStakedAmount && currentService.left == 0) {
                    services[service] = Service({index: service, left: 0, right: currentService.index, amount: totalStakedAmount});
                    currentService.left = service;
                    break;
                }

                currentServiceIndex = currentService.left;
            }
        }
    }
}
