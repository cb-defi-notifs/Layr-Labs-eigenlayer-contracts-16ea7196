// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./IInvestmentStrategy.sol";

//TODO: discuss if we can structure the inputs of these functions better
interface IDelegationTerms {
    function payForService(
        IERC20 token,
        uint256 amount
    ) external payable;

    function onDelegationWithdrawn(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external;

    // function onDelegationReceived(
    //     address delegator,
    //     uint256[] memory investorShares
    // ) external;

    function onDelegationReceived(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external;
}