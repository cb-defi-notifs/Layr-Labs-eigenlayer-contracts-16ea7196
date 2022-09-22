// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./IDelegationTerms.sol";

interface IEigenLayrDelegation {
    enum DelegationStatus {
        UNDELEGATED,
        DELEGATED
    }

    function registerAsDelegate(IDelegationTerms dt) external;

    function delegationTerms(address operator) external view returns (IDelegationTerms);

    function operatorShares(address operator, IInvestmentStrategy investmentStrategy) external view returns (uint256);

    function isNotDelegated(address staker) external returns (bool);

    function delegation(address delegator) external view returns (address);

    function undelegate(address staker) external;

    function isDelegated(address staker) external view returns (bool);

    function isOperator(address operator) external view returns (bool);

    function decreaseDelegatedShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    )
        external;

    function increaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares) external;

    function decreaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares) external;
}
