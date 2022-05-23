// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IDelegationTerms.sol";

interface IEigenLayrDelegation {
    enum DelegationStatus {
        UNDELEGATED,
        DELEGATED,
        UNDELEGATION_COMMITED,
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

    function getConsensusLayerEthDelegated(address operator)
        external
        view
        returns (uint256);

    function getEigenDelegated(address operator)
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

    function isSelfOperator(address operator)
        external
        view
        returns (bool);

    function decreaseOperatorShares(
        address operator,
        IInvestmentStrategy strategy,
        uint256 shares
    ) external;
    
    function decreaseOperatorShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;

    function increaseOperatorShares(
        address operator,
        IInvestmentStrategy strategy,
        uint256 shares
    ) external;

    function increaseOperatorShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;

    function decreaseOperatorEigen(address operator, uint256 eigenAmount) external;

    function increaseOperatorEigen(address operator, uint256 eigenAmount) external;
    
}
