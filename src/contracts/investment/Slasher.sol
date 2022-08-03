// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IServiceFactory.sol";
import "../interfaces/IRepository.sol";
import "../interfaces/ISlasher.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentManager.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import "forge-std/Test.sol";


/**
 * @notice This contract specifies details on slashing. The functionalities are:
 *          - adding contracts who have permission to perform slashing,
 *          - revoking permission for slashing from specified contracts,
 *          - calling investManager to do actual slashing.          
 */
contract Slasher is 
    Initializable,
    OwnableUpgradeable,
    ISlasher
    ,DSTest 
{
    IInvestmentManager public investmentManager;
    IEigenLayrDelegation public delegation;
    mapping(address => bool) public globallyPermissionedContracts;
    mapping(address => bool) public serviceFactories;
    // user => contract => if that contract can slash the user
    mapping(address => mapping(address => bool)) public optedIntoSlashing;
    // staker => if they are 'slashed' or not
    mapping(address => bool) public slashedStatus;

    constructor(){
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    function initialize(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation,
        address _eigenLayrGovernance
    ) external initializer {
        investmentManager = _investmentManager;
        delegation = _delegation;
        _transferOwnership(_eigenLayrGovernance);
        // TODO: add EigenLayrDelegation to list of permissioned contracts -- at least in testing, but possibly here in the constructor
    }

    /**
     * @notice used for giving permission of slashing to contracts. 
     */
    function addPermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            globallyPermissionedContracts[contracts[i]] = true;
            unchecked {
                ++i;
            }
        } 
    }

    /**
     * @notice used for revoking permission of slashing from contracts. 
     */
    function removePermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            globallyPermissionedContracts[contracts[i]] = false;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice used for marking approved service factories 
     */
    function addserviceFactories(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            serviceFactories[contracts[i]] = true;
            unchecked {
                ++i;
            }
        } 
    }

    /**
     * @notice used for revoking approval of service factories
     */
    function removeserviceFactories(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            serviceFactories[contracts[i]] = false;
            unchecked {
                ++i;
            }
        }
    }

// TODO: make it so a repository contract can revoke its ability to slash your funds
    // give the contract permission to slash your funds
    function allowToSlash(address repository) external {
        optedIntoSlashing[msg.sender][repository] = true;

        uint number = optedIntoSlashing[msg.sender][repository] ? uint(1) : uint(0);
        emit log_named_uint("Permission to slash", number);
        
    }

    // TODO: safe way to opt OUT of slashing (fraudproof)
    // TODO: Why are we passing in registry here instead of getting it from the repository?
    // idea -- require registry of repository to call function that opts you out

    // NOTE: 'serviceFactory' does not have to be supplied in the event that the user has opted-in directly
    function canSlash(address toBeSlashed, IServiceFactory serviceFactory, IRepository repository, IRegistry registry) public returns (bool) {
        // if the user has directly opted in to the 'repository' address being allowed to slash them
        emit log_address(toBeSlashed);
        uint number = optedIntoSlashing[toBeSlashed][address(repository)] ? uint(1) : uint(0);
        emit log_named_uint("Permission to slash", number);
        if (optedIntoSlashing[toBeSlashed][address(repository)]
            || 
            (
                // if specified 'serviceFactory' address is included in the approved list of service factories
                (serviceFactories[address(serviceFactory)])
            &&
                // if both 'repository' and 'registry' were created by 'serviceFactory' (and are the correct contract type)
                (serviceFactory.isRepository(repository) && serviceFactory.isRegistry(registry))
            )
            )
        {
            // if 'registry' is the active Registry in 'repository'
            if (
                (repository.registry() == registry)
                &&
                // if address 'toBeSlashed' is a registered operator in 'registry'
                (registry.isRegistered(toBeSlashed))
                )
            {
                return true;
            }
        }
        // else return 'false'
        return false;
    }

    /**
     * @notice Used for slashing a certain operator
     */
    function slashOperator(address toBeSlashed, IServiceFactory serviceFactory, IRepository repository, IRegistry registry) external {
        require(canSlash(toBeSlashed, serviceFactory, repository, registry), "cannot slash operator");
        // TODO: add more require statements, particularly on msg.sender
        revert();
        slashedStatus[toBeSlashed] = true;
    }

    /**
     * @notice used for calling slashing function in investmentManager contract.
     */
    function slashOperator(
        address toBeSlashed
    ) external {
        require(globallyPermissionedContracts[msg.sender], "Only permissioned contracts can slash");
        slashedStatus[toBeSlashed] = true;
    }

    function resetSlashedStatus(address[] calldata slashedAddresses) external onlyOwner {
        for (uint256 i = 0; i < slashedAddresses.length; ) {
            slashedStatus[slashedAddresses[i]] = false;
            unchecked { ++i; }
        }
    }

    function hasBeenSlashed(address staker) external view returns (bool) {
        if (slashedStatus[staker]) {
            return true;
        } else if (delegation.isDelegated(staker)) {
            address operatorAddress = delegation.delegation(staker);
            return(slashedStatus[operatorAddress]);
        } else {
            return false;
        }
    }
}
