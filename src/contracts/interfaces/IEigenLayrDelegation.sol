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

    function getDelegationTerms(address operator)
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

    // TODO: finalize this function
    function reduceOperatorShares(
        address operator,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata shares
    ) external;

    function isDelegatedToSelf(address operator)
        external
        view
        returns (bool);
}
