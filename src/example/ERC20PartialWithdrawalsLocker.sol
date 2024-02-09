// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Locker} from "../template/Locker.sol";

/// @title ERC20PartialWithdrawalsLocker
/// @author Polygon Labs
/// @notice An ERC20-compatible abstract template contract inheriting from Locker
/// @notice Enables partial withdrawals by tracking slashing risk
abstract contract ERC20PartialWithdrawalsLocker is Locker {
    // TODO add tracking onSlash?

    mapping(address staker => mapping(uint256 => Service)) services;
    uint256 highestStakeService;

    struct Service {
        uint256 index;
        uint256 left;
        uint256 right;
        uint256 amount; // yes, this tracks same amount as balancesIn, but more convenient to also have it here.
    }

    constructor(address _stakingHub) Locker(_stakingHub) {}

    // FUNCTIONS TO IMPLEMENT
    // more in Locker
    function _withdraw(uint256 amount) internal virtual;

    function withdraw(uint256 amount) external virtual {
        require(_withdrawableAmount() >= amount, "ERC20PartialWithdrawalsLocker: amount exceeds withdrawable amount");
        _withdraw(amount);
    }

    /// @dev returns amount of veTKN that can be withdrawn
    function _withdrawableAmount() internal view returns (uint256 amount) {
        uint256 slashable = slashableAmount[msg.sender];
        uint256 highestStake = services[msg.sender][highestStakeService].amount;

        // use highest
        return balanceOf(msg.sender) - highestStake >= slashable ? highestStake : slashable;
    }

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Locker.
    /// @dev Triggered before `onRestake` on the Service.
    function _onRestake(
        address staker,
        uint256 service,
        uint256 stakingAmount,
        uint8 maxSlashingPercentage
    ) internal override {
        uint256 totalStakedAmount = services[staker][service].amount;

        updateHighestStake(staker, service, totalStakedAmount);
    }

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Locker.
    /// @dev Triggered after `onUnstake` on the Service.
    function _onUnstake(address staker, uint256 service, uint256 amount) internal override {
        // review only allow unstaking the same amount that you staked before.
        // we can avoid loops in the onUnstake hook this way!

        // delete service entry
        Service memory serviceEntry = services[staker][service];
        services[staker][serviceEntry.left].right = serviceEntry.right;
        services[staker][serviceEntry.right].left = serviceEntry.left;
        delete services[staker][service];

        // update highestStakeService if necessary
        if (service == highestStakeService) {
            highestStakeService = serviceEntry.left;
        }
    }

    function updateHighestStake(address staker, uint256 service, uint256 totalStakedAmount) private {
        // new high, if first entry, second line won't have any effect
        if (services[staker][highestStakeService].amount <= totalStakedAmount) {
            services[staker][service] = Service({index: service, left: highestStakeService, right: 0, amount: totalStakedAmount});
            services[staker][highestStakeService].right = service;
            highestStakeService = service;
        } else {
            // sort it in
            uint256 currentServiceIndex = services[staker][highestStakeService].left;
            while (true) {
                Service memory currentService = services[staker][currentServiceIndex];

                // found lower entry
                if (currentService.amount < totalStakedAmount) {
                    Service memory higherService = services[staker][currentService.right];
                    services[staker][service] = Service({index: service, left: currentService.index, right: higherService.index, amount: totalStakedAmount});
                    higherService.left = service;
                    currentService.right = service;
                    break;
                }

                // found bottom
                if (currentService.amount > totalStakedAmount && currentService.left == 0) {
                    services[staker][service] = Service({index: service, left: 0, right: currentService.index, amount: totalStakedAmount});
                    currentService.left = service;
                    break;
                }

                currentServiceIndex = currentService.left;
            }
        }
    }
}
