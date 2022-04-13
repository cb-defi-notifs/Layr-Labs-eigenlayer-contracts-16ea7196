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

    function registerAsDelgate(IDelegationTerms dt) external;

    function getDelegationTerms(address operator)
        external
        view
        returns (IDelegationTerms);

        //TODO: do we need this?
    // function getOperatorShares(address operator)
    //     external
    //     view
    //     returns (IInvestmentStrategy[] memory);

    function getUnderlyingEthDelegated(address operator)
        external
        returns (uint256);

    function getUnderlyingEthDelegatedView(address operator)
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

    function getControlledEthStake(address operator)
        external
        view
        returns (IInvestmentStrategy[] memory, uint256[] memory, uint256);

    function isNotDelegated(address staker)
        external
        view
        returns (bool);

    function delegation(address delegator)
        external
        view
        returns (address);
}
