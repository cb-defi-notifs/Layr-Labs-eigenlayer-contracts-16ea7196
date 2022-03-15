// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./IQueryManager.sol";
import "./IInvestmentStrategy.sol";

interface IDelegationTerms {
    function payForService(
        IERC20 token,
        uint256 amount
    ) external payable;

    function onDelegationWithdrawn(
        address staker,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;

    function onDelegationReceived(
        address staker,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;
}