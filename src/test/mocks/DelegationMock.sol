// //SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IEigenLayerDelegation.sol";


contract DelegationMock is IEigenLayerDelegation, Test {
    mapping (address => address) public delegatedTo;

    function registerAsOperator(IDelegationTerms /*dt*/) external {}

    function delegateTo(address operator) external {
        delegatedTo[msg.sender] = operator;
    }


    function delegateToBySignature(address /*staker*/, address /*operator*/, uint256 /*expiry*/, bytes memory /*signature*/) external {}


    function undelegate(address staker) external {
        delegatedTo[staker] = address(0);
    }

    /// @notice returns the DelegationTerms of the `operator`, which may mediate their interactions with stakers who delegate to them.
    function delegationTerms(address /*operator*/) external view returns (IDelegationTerms) {}

    /// @notice returns the total number of shares in `strategy` that are delegated to `operator`.
    function operatorShares(address /*operator*/, IInvestmentStrategy /*strategy*/) external view returns (uint256) {}


    function increaseDelegatedShares(address /*staker*/, IInvestmentStrategy /*strategy*/, uint256 /*shares*/) external {}

    function decreaseDelegatedShares(
        address /*staker*/,
        IInvestmentStrategy[] calldata /*strategies*/,
        uint256[] calldata /*shares*/
    ) external {}

    function isDelegated(address staker) external view returns (bool) {
        return (delegatedTo[staker] != address(0));
    }

    function isNotDelegated(address /*staker*/) external pure returns (bool) {}

    function isOperator(address /*staker*/) external view returns (bool) {}


}