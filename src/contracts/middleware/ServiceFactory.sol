// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IServiceFactory.sol";
import "./Repository.sol";

/**
 * @notice This factory contract is used for launching new repository contracts.
 */


contract ServiceFactory is IServiceFactory {
    mapping(IRepository => bool) public isRepository;
    IInvestmentManager immutable investmentManager;
    IEigenLayrDelegation immutable delegation;

    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _delegation) {
        investmentManager = _investmentManager;
        delegation = _delegation;
    }


    /**
     *  @notice Used for creating new repository contracts with given specifications.
     */
    /**
     * @param feeManager is the contract for managing fees,
     * @param voteWeigher is the contract for determining how much vote to be assigned to
     *        the response from an operator for the purpose of computing the outcome of the query, 
     * @param registrationManager is the address of the contract that manages registration of operators
     *        with the middleware of the repository that is being created,  
     * @param timelockDelay is the intended delay on the governing timelock. 
     */ 
    function createNewRepository(
        IFeeManager feeManager,
        IVoteWeigher voteWeigher,
        IRegistrationManager registrationManager,
        uint256 timelockDelay
    ) external returns(IRepository) {
        // register a new repository
        IRepository newRepository = new Repository();
        Repository(payable(address(newRepository))).initialize(
            voteWeigher,
            feeManager,
            registrationManager,
            timelockDelay,
            delegation,
            investmentManager
        );

        // set the existence bit on the repository to true
        isRepository[newRepository] = true;
        return newRepository;
    }


    /// @notice used for checking if the repository exists  
    function repositoryExists(IRepository repository)
        external
        view
        returns (bool)
    {
        return isRepository[repository];
    }
}
