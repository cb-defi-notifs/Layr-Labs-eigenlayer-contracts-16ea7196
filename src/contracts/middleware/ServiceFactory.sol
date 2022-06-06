// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IServiceFactory.sol";
import "./Repository.sol";
import "./VoteWeigherBase.sol";
import "./RegistrationManagerBase.sol";

/**
 * @notice This factory contract is used for launching new repository contracts.
 */


contract ServiceFactory is IServiceFactory {
    mapping(IRepository => bool) public isRepository;
    mapping(IRegistrationManager => bool) public isRegistrationManager;
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
     * @param serviceManager is the contract for managing fees,
     * @param voteWeigher is the contract for determining how much vote to be assigned to
     *        the response from an operator for the purpose of computing the outcome of the query, 
     * @param registrationManager is the address of the contract that manages registration of operators
     *        with the middleware of the repository that is being created,  
     * @param initialOwner is the inital owner of the repository contract 
     */ 
    function createNewRepository(
        IServiceManager serviceManager,
        IVoteWeigher voteWeigher,
        IRegistrationManager registrationManager,
        address initialOwner
    ) external returns(IRepository) {
        // register a new repository
        IRepository newRepository = new Repository(delegation, investmentManager);
        Repository(payable(address(newRepository))).initialize(
            voteWeigher,
            serviceManager,
            registrationManager,
            initialOwner
        );

        // set the existence bit on the repository to true
        isRepository[newRepository] = true;
        return newRepository;
    }

    function createNewService(
        IServiceManager serviceManager,
        uint256 timelockDelay,
        uint256 _consensusLayerEthToEth,
        IInvestmentStrategy[] memory _strategiesConsidered,
        address initialRepositoryOwner
    ) external returns(IRepository, IRegistrationManager, IVoteWeigher) {
        IRepository repository = new Repository(delegation, investmentManager);
        IVoteWeigher voteWeigher = new VoteWeigherBase(repository, delegation, investmentManager, _consensusLayerEthToEth, _strategiesConsidered);
        IRegistrationManager registrationManager = new RegistrationManagerBase(repository);
        Repository(payable(address(repository))).initialize(
            voteWeigher,
            serviceManager,
            registrationManager,
            initialRepositoryOwner
        );
        // set the existence bit on the repository and registration manager to true
        isRepository[repository] = true;
        isRegistrationManager[registrationManager] = true;
        return (repository, registrationManager, voteWeigher);
    }
}
