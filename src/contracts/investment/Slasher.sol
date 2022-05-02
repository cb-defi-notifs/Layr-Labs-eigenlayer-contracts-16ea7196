// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./InvestmentManager.sol";
import "../utils/Governed.sol";
import "../interfaces/IServiceFactory.sol";
import "../interfaces/IRepository.sol";

/**
 * @notice This contract specifies details on slashing. The functionalities are:
 *          - adding contracts who have permission to perform slashing,
 *          - revoking permission for slashing from specified contracts,
 *          - calling investManager to do actual slashing.          
 */
contract Slasher is Governed {
    InvestmentManager public investmentManager;
    mapping(address => bool) public globallyPermissionedContracts;
    mapping(address => bool) public serviceFactories;
    // user => contract => if that contract can slash the user
    mapping(address => mapping(address => bool)) public optedIntoSlashing;

    constructor(InvestmentManager _investmentManager, address _eigenLayrGovernance) {
        _transferGovernor(_eigenLayrGovernance);
        investmentManager = _investmentManager;
    }

    /**
     * @notice used for giving permission of slashing to contracts. 
     */
    function addPermissionedContracts(address[] calldata contracts) external onlyGovernor {
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
    function removePermissionedContracts(address[] calldata contracts) external onlyGovernor {
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
    function addserviceFactories(address[] calldata contracts) external onlyGovernor {
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
    function removeserviceFactories(address[] calldata contracts) external onlyGovernor {
        for (uint256 i = 0; i < contracts.length;) {
            serviceFactories[contracts[i]] = false;
            unchecked {
                ++i;
            }
        }
    }

    // give the contract permission to slash your funds
    function allowToSlash(address repository) external {
        optedIntoSlashing[msg.sender][repository] = true;
    }

    // TODO: safe way to opt OUT of slashing (fraudproof)
    // idea -- require registrationManager of repository to call function that opts you out

    // NOTE: 'serviceFactory' does not have to be supplied in the event that the user has opted-in directly
    function canSlash(address toBeSlashed, IServiceFactory serviceFactory, IRepository repository, IRegistrationManager registrationManager) public view returns (bool) {
        // if the user has directly opted in to the 'repository' address being allowed to slash them
        if (optedIntoSlashing[toBeSlashed][address(repository)]
            || 
            (
                // if specified 'serviceFactory' address is included in the approved list of service factories
                (serviceFactories[address(serviceFactory)])
            &&
                // if both 'repository' and 'registrationManager' were created by 'serviceFactory' (and are the correct contract type)
                (serviceFactory.isRepository(repository) && serviceFactory.isRegistrationManager(registrationManager))
            )
            )
        {
            // if 'registrationManager' is the active RegistrationManager in 'repository'
            if (
                (repository.registrationManager() == registrationManager)
                &&
                // if address 'toBeSlashed' is a registered operator in 'registrationManager'
                (registrationManager.isRegistered(toBeSlashed))
                )
            {
                return true;
            }
        }
        // else return 'false'
        return false;
    }

    /**
     * @notice used for calling slashing function in investmentManager contract.
     */
    function slashShares(
        address slashed,
        address recipient,
        IInvestmentStrategy[] calldata strategies,
        uint256[] calldata amounts,
        uint256 maxSlashedAmount
    ) external {
        require(globallyPermissionedContracts[msg.sender], "Only permissioned contracts can slash");
        investmentManager.slashShares(slashed, recipient, strategies, amounts, maxSlashedAmount);
    }
}
