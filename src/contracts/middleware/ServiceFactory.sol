// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IServiceFactory.sol";
import "./QueryManager.sol";

/**
 * @notice This factory contract is used for launching new query manager contracts.
 */


contract ServiceFactory is IServiceFactory {
    mapping(IQueryManager => bool) public isQueryManager;
    IInvestmentManager immutable investmentManager;
    IEigenLayrDelegation immutable delegation;

    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _delegation) {
        investmentManager = _investmentManager;
        delegation = _delegation;
    }


    /**
     *  @notice Used for creating new query manager contracts with given specifications.
     */
    /**
     * @param feeManager is the contract for managing fees,
     * @param voteWeigher is the contract for determining how much vote to be assigned to
     *        the response from an operator for the purpose of computing the outcome of the query, 
     * @param registrationManager is the address of the contract that manages registration of operators
     *        with the middleware of the query manager that is being created,  
     * @param timelockDelay is the intended delay on the governing timelock. 
     */ 
    function createNewQueryManager(
        IFeeManager feeManager,
        IVoteWeigher voteWeigher,
        IRegistrationManager registrationManager,
        uint256 timelockDelay
    ) external returns(IQueryManager) {
        // register a new query manager
        IQueryManager newQueryManager = new QueryManager();
        QueryManager(payable(address(newQueryManager))).initialize(
            voteWeigher,
            feeManager,
            registrationManager,
            timelockDelay,
            delegation,
            investmentManager
        );

        // set the existence bit on the query manager to true
        isQueryManager[newQueryManager] = true;
        return newQueryManager;
    }


    /// @notice used for checking if the query manager exists  
    function queryManagerExists(IQueryManager queryManager)
        external
        view
        returns (bool)
    {
        return isQueryManager[queryManager];
    }
}
