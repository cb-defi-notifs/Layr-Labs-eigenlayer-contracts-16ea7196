// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

/**
 * @title Interface for the primary 'slashing' contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice See the `Slasher` contract itself for implementation details.
 */
interface ISlasher {
    function freezeOperator(address toSlash) external;

    function isFrozen(address staker) external view returns (bool);

    function revokeSlashingAbility(address operator, uint32 unbondedAfter) external;

    function frozenStatus(address operator) external view returns (bool);

    function resetFrozenStatus(address[] calldata frozenAddresses) external;

    function bondedUntil(address operator, address slashingContract) external view returns (uint32);

    function canSlash(address toBeSlashed, address slashingContract) external view returns (bool);
}
