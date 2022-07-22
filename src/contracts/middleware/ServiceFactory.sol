// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IServiceFactory.sol";
import "./Repository.sol";
import "./VoteWeigherBase.sol";
import "./BLSRegistry.sol";
import "./BLSRegistryFactory.sol";
// import "./RegistryBase.sol";

/**
 * @notice This factory contract is used for launching new repository contracts.
 */


contract ServiceFactory is IServiceFactory {

    IInvestmentManager immutable investmentManager;
    IEigenLayrDelegation immutable delegation;
    // TODO: set the address for this, likely in the constructor
    BLSRegistryFactory public blsRegistryFactory;

    mapping(IRepository => bool) public isRepository;
    mapping(IRegistry => bool) public isRegistry;

    constructor(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation
    ) {
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
     * @param registry is the address of the contract that manages registration of operators
     *        with the middleware of the repository that is being created,  
     * @param initialOwner is the inital owner of the repository contract 
     */ 
    function createNewRepository(
        IServiceManager serviceManager,
        IVoteWeigher voteWeigher,
        IRegistry registry,
        address initialOwner
    ) external returns(IRepository) {
        // register a new repository
        IRepository newRepository = new Repository(delegation, investmentManager);
        Repository(address(newRepository)).initialize(
            voteWeigher,
            serviceManager,
            registry,
            initialOwner
        );

        // set the existence bit on the repository to true
        isRepository[newRepository] = true;
        return newRepository;
    }


    function createNewService(
        IServiceManager serviceManager,
        address initialRepositoryOwner,
        uint8 _NUMBER_OF_QUORUMS,
        BLSRegistry.StrategyAndWeightingMultiplier[] memory _ethStrategiesConsideredAndMultipliers,
        BLSRegistry.StrategyAndWeightingMultiplier[] memory _eigenStrategiesConsideredAndMultipliers
    ) external returns(IRepository, IRegistry, IVoteWeigher) {
        IRepository repository = new Repository(delegation, investmentManager);
        IVoteWeigher voteWeigher = new VoteWeigherBase(repository, delegation, investmentManager, _NUMBER_OF_QUORUMS);
        IRegistry registry = blsRegistryFactory.createNewBLSRegistry(Repository(address(repository)), delegation, investmentManager, _ethStrategiesConsideredAndMultipliers, _eigenStrategiesConsideredAndMultipliers);
        Repository(address(repository)).initialize(
            voteWeigher,
            serviceManager,
            registry,
            initialRepositoryOwner
        );
        // set the existence bit on the repository and Registry to true
        isRepository[repository] = true;
        isRegistry[registry] = true;
        return (repository, registry, voteWeigher);
    }
}
