// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

/**
 * @title Interface for the primary 'slashing' contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice See the `Slasher` contract itself for implementation details.
 */
interface ISlasher {
    struct MiddlewareTimes {
        uint32 updateTime; //the time at which this MiddlewareTimes update was appended
        uint32 leastRecentUpdateTime; //the time of update for the middleware whose latest update was earliest
        uint32 latestServeUntil; //the latest serve until time from all of the middleware that the operator is serving
    }

    function freezeOperator(address toSlash) external;

    function isFrozen(address staker) external view returns (bool);

    function revokeSlashingAbility(address operator, uint32 unbondedAfter) external;

    function frozenStatus(address operator) external view returns (bool);

    function resetFrozenStatus(address[] calldata frozenAddresses) external;

    function bondedUntil(address operator, address slashingContract) external view returns (uint32);

    function canSlash(address toBeSlashed, address slashingContract) external view returns (bool);

    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external;

    function recordStakeUpdate(address operator, uint32 serveUntil) external;
    
    function recordLastStakeUpdate(address operator, uint32 serveUntil) external;
}
