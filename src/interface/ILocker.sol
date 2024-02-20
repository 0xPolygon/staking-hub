// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title Locker
 * @author Polygon Labs
 * @notice
 * Plese see PRC-X for more details.
 */
interface ILocker {
    /**
     * @notice
     * Indicates change in balance. Monitored by services offchain.
     * @dev
     * Must be logged on balance change (depositing, initiating withdrawal, slashing, etc.).
     * @param staker Staker.
     * @param newBalance New balance.
     */
    event BalanceChanged(address staker, uint256 newBalance);

    /**
     * @dev
     * Should be logged on withdrawal.
     * @param staker Staker.
     * @param amount Amount.
     */
    event Withdrawn(address staker, uint256 amount);

    /**
     * @notice
     * Does internal accounting. Should perform risk managment.
     * @dev
     * Triggered by hub.
     * @param staker Staker.
     * @param service Service.
     * @param maxSlashPercentage Max slash percentage. Used for managing risk.
     */
    function onSubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external;

    /**
     * @notice
     * Does internal accounting. Should perform risk managment.
     * @dev
     * Triggered by hub.
     * @param staker Staker.
     * @param service Service.
     * @param maxSlashPercentage Max slash percentage. Used for managing risk.
     */
    function onUnsubscribe(address staker, uint256 service, uint8 maxSlashPercentage) external;

    /**
     * @notice
     * Must burn slashed funds. Must aggregates slashings by applying percentage to balance at start of freeze period. Must burn funds scheduled for withdrawal first.
     * @dev
     * Triggered by hub.
     * Logs `BalanceChanged`.
     * @param staker Staker.
     * @param service Service.
     * @param percentage Percentage.
     * @param freezeStart Freeze period ID. Used to snapshot balance once at start of freeze period for slashing aggregation.
     */
    function onSlash(address staker, uint256 service, uint8 percentage, uint40 freezeStart) external;

    /**
     * @return Locker ID.
     */
    function id() external view returns (uint256);

    /**
     * @return amount Underlying funds of staker.
     */
    function balanceOf(address staker) external view returns (uint256 amount);

    /**
     * @return amount Underlying funds of staker, restaked in service.
     */
    function balanceOf(address staker, uint256 service) external view returns (uint256 amount);

    /**
     * @return votingPower Representation of voting power of staker.
     */
    function votingPowerOf(address staker) external view returns (uint256 votingPower);

    /**
     * @return votingPower Representation of voting power of staker in service.
     */
    function votingPowerOf(address staker, uint256 service) external view returns (uint256 votingPower);

    /**
     * @return Underlying funds of all stakers.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @return Underlying funds of all stakers restaked in service.
     */
    function totalSupply(uint256 service) external view returns (uint256);

    /**
     * @return Representation of voting power of all stakers.
     */
    function totalVotingPower() external view returns (uint256);

    /**
     * @return Representation of voting power of all stakers in service.
     */
    function totalVotingPower(uint256 service) external view returns (uint256);

    /**
     * @return Services staker is subscribed to that use locker.
     */
    function getServices(address staker) external view returns (uint256[] memory);

    /**
     * @return Whether staker is subscribed to service.
     */
    function isSubscribed(address staker, uint256 service) external view returns (bool);
}
