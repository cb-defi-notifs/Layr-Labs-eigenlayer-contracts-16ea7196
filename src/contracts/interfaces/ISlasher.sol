// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceFactory.sol";
import "./IInvestmentStrategy.sol";

interface ISlasher {
    function freezeOperator(
        address toSlash
    ) external;

    function isFrozen(
        address staker
    ) external view returns(bool);

    function frozenStatus(address operator) external view returns (bool);

    function resetFrozenStatus(address[] calldata frozenAddresses) external;

    function canSlash(address toBeSlashed, address slashingContract) external view returns (bool);
}
