// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceFactory.sol";
import "./IInvestmentStrategy.sol";

interface ISlasher {
    function canSlash(address toBeSlashed, IServiceFactory serviceFactory, IRepository repository, IRegistrationManager registrationManager) external view returns (bool);

    function slashShares(
        address slashed,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata strategyIndexes,
        uint256[] calldata amounts,
        uint256 maxSlashedAmount
    ) external;
}
