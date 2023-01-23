// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.12;

import "./IInvestmentStrategy.sol";

/**
 * @title Abstract interface for a contract that helps structure the delegation relationship.
 * @author Layr Labs, Inc.
 * @notice The gas budget provided to this contract in calls from EigenLayer contracts is limited.
 */
interface IDelegationTerms {
    function payForService(IERC20 token, uint256 amount) external payable;

    function onDelegationWithdrawn(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external;

    function onDelegationReceived(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external;
}
