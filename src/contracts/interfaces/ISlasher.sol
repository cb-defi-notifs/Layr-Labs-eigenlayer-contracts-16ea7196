// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

interface ISlasher {
    function freezeOperator(address toSlash) external;

    function isFrozen(address staker) external view returns (bool);

    function revokeSlashingAbility(address operator) external;

    function frozenStatus(address operator) external view returns (bool);

    function resetFrozenStatus(address[] calldata frozenAddresses) external;

    function canSlash(address toBeSlashed, address slashingContract) external view returns (bool);
}
