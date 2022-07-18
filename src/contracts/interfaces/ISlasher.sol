// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IServiceFactory.sol";
import "./IInvestmentStrategy.sol";

interface ISlasher {
    function canSlash(
        address toBeSlashed,
        IServiceFactory serviceFactory,
        IRepository repository,
        IRegistry registry
    ) external  returns (bool);

    function slashOperator(
        address toSlash
    ) external;
}
