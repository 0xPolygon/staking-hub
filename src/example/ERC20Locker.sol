// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Locker} from "../template/Locker.sol";
import {StakingLayer} from "../StakingLayer.sol";

/// @title ERC20Locker
/// @author Polygon Labs
/// @notice An ERC20-compatible abstract template contract inheriting from BaseLocker
abstract contract ERC20Locker is ERC20Burnable, Locker {
    IERC20 public immutable underlying; // Must not allow reentrancy

    // TODO add events

    constructor(IERC20 _underlying, string memory name, string memory symbol, address _stakingHub) ERC20(name, symbol) Locker(_stakingHub) {
        underlying = _underlying;
    }

    function balanceOf(address account) public view override(ERC20, Locker) returns (uint256) {
        return ERC20.balanceOf(account);
    }

    function deposit(uint256 amount) external {
        _deposit(msg.sender, amount);
    }

    function depositFor(address user, uint256 amount) external {
        _deposit(user, amount);
    }

    function depositPermit(uint256 amount) external {
        // TODO
    }

    function _deposit(address to, uint256 amount) private {
        _mint(to, amount);
        underlying.transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) external {
        // require(Hub(stakingHub).hasActiveSubscriptions(msg.sender) == false, "ERC20Locker: Cannot withdraw: active subscription");

        _burn(msg.sender, amount);
        underlying.transfer(msg.sender, amount);
    }

    /// @dev Triggered by the Hub when a Staker restakes to a Services that uses the Locker.
    /// @dev Triggered before `onRestake` on the Service.
    function _onRestake(address staker, uint256 service, uint256 lockingInUntil, uint256 stakingAmount, uint8 maximumSlashingPercentage) internal override {}

    /// @dev Called by the Hub when a Staker has unstaked from a Service that uses the Locker.
    /// @dev Triggered after `onUnstake` on the Service.
    function _onUnstake(address staker, uint256 service, uint256 amount) internal override {}

    function _onSlash(address user, uint256 service, uint256 amount) internal override {
        _burn(user, amount);
    }

    function totalSupply() public view override(ERC20, Locker) returns (uint256) {}
}
