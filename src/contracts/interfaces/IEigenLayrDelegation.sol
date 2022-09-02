// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "./IDelegationTerms.sol";

interface IEigenLayrDelegation {
    enum DelegationStatus {
        UNDELEGATED,
        DELEGATED,
        UNDELEGATION_INITIALIZED,
        UNDELEGATION_COMMITTED
    }

    function registerAsDelegate(IDelegationTerms dt) external;

    function delegationTerms(address operator)
        external
        view
        returns (IDelegationTerms);

    function operatorShares(address operator, IInvestmentStrategy investmentStrategy)
        external
        view
        returns (uint256);

    function isNotDelegated(address staker)
        external
        returns (bool);

    function delegation(address delegator)
        external
        view
        returns (address);

    function isDelegated(address staker)
        external
        view
        returns (bool);

    function isDelegate(address operator)
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