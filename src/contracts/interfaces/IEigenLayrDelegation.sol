// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IDelegationTerms.sol";

interface IEigenLayrDelegation {
    enum DelegationStatus {
        UNDELEGATED,
        DELEGATED,
        UNDELEGATION_COMMITTED,
        UNDELEGATION_FINALIZED
    }

    function registerAsDelegate(IDelegationTerms dt) external;

    function delegationTerms(address operator)
        external
        view
        returns (IDelegationTerms);

    function getOperatorShares(address operator, IInvestmentStrategy investmentStrategy)
        external
        view
        returns (uint256);

    function isNotDelegated(address staker)
        external
        view
        returns (bool);

    function delegation(address delegator)
        external
        view
        returns (address);

    function isDelegator(address operator)
        external
        view
        returns (bool);
    
    function decreaseDelegatedShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;

    function increaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares) external;

    function decreaseDelegatedShares(address staker, IInvestmentStrategy strategy, uint256 shares) external;
}
