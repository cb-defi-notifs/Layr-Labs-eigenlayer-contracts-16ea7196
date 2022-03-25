// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IERC20.sol";
import "../interfaces/IServiceFactory.sol";
import "./QueryManager.sol";

contract ServiceFactory is IServiceFactory {
    mapping(IQueryManager => bool) public isQueryManager;
    IInvestmentManager immutable investmentManager;

    constructor(IInvestmentManager _investmentManager) {
        investmentManager = _investmentManager;
    }

    function createNewQueryManager(
        uint256 queryDuration,
        uint256 consensusLayerEthToEth,
        IFeeManager feeManager,
        IVoteWeighter voteWeigher,
        address registrationManager,
        address timelock,
        IEigenLayrDelegation delegation
    ) external {
        // register a new query manager
        IQueryManager newQueryManager = new QueryManager(voteWeigher);
        QueryManager(payable(address(newQueryManager))).initialize(
            queryDuration,
            consensusLayerEthToEth,
            feeManager,
            registrationManager,
            timelock,
            delegation,
            investmentManager
        );
        isQueryManager[newQueryManager] = true;
    }

    function queryManagerExists(IQueryManager queryManager)
        external
        view
        returns (bool)
    {
        return isQueryManager[queryManager];
    }
}
