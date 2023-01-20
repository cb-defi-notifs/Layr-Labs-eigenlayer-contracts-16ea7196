// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IDelegationTerms.sol";

contract DelegationTermsMock is IDelegationTerms, Test {

    bool public shouldRevert;

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function payForService(IERC20 token, uint256 amount) external payable {

    }

    function onDelegationWithdrawn(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external {
        if (shouldRevert) {
            revert("reverting as intended");
        }
    }

    function onDelegationReceived(
        address delegator,
        IInvestmentStrategy[] memory investorStrats,
        uint256[] memory investorShares
    ) external {
        if (shouldRevert) {
            revert("reverting as intended");
        }

    }

}