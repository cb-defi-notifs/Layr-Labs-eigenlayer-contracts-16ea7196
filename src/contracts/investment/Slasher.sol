// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9.0;

import "../interfaces/IRepository.sol";
import "../interfaces/ISlasher.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentManager.sol";
import "../utils/Pausable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import "forge-std/Test.sol";


/**
 * @title The primary 'slashing' contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice This contract specifies details on slashing. The functionalities are:
 *          - adding contracts who have permission to perform slashing,
 *          - revoking permission for slashing from specified contracts,
 *          - calling investManager to do actual slashing.          
 */
contract Slasher is 
    Initializable,
    OwnableUpgradeable,
    ISlasher,
    Pausable
    // ,DSTest 
{
    /// @notice The central InvestmentManager contract of EigenLayr
    IInvestmentManager public investmentManager;
    /// @notice The EigenLayrDelegation contract of EigenLayr
    IEigenLayrDelegation public delegation;
    // contract address => whether or not the contract is allowed to slash any staker (or operator) in EigenLayr
    mapping(address => bool) public globallyPermissionedContracts;
    // user => contract => if that contract can slash the user
    mapping(address => mapping(address => bool)) public optedIntoSlashing;
    // staker => if their funds are 'frozen' and potentially subject to slashing or not
    mapping(address => bool) public frozenStatus;

    event GloballyPermissionedContractAdded(address indexed contractAdded);
    event GloballyPermissionedContractRemoved(address indexed contractRemoved);
    event OptedIntoSlashing(address indexed operator, address indexed contractAddress);
    event SlashingAbilityRevoked(address indexed operator, address indexed contractAddress);
    event OperatorSlashed(address indexed slashedOperator, address indexed slashingContract);
    event FrozenStatusReset(address indexed previouslySlashedAddress);

    constructor(){
        // TODO: uncomment for production use!
        //_disableInitializers();
    }

    // EXTERNAL FUNCTIONS
    function initialize(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation,
        IPauserRegistry pauserRegistry,
        address _eigenLayrGovernance
    ) external initializer {
        _initializePauser(pauserRegistry);
        investmentManager = _investmentManager;
        delegation = _delegation;
        _transferOwnership(_eigenLayrGovernance);
        // add EigenLayrDelegation to list of permissioned contracts
        _addGloballyPermissionedContract(address(_delegation));
    }

    /// @notice Used to give global slashing permission to specific contracts. 
    function addGloballyPermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            _addGloballyPermissionedContract(contracts[i]);
            unchecked {
                ++i;
            }
        } 
    }

    /// @notice Used to revoke global slashing permission from contracts. 
    function removeGloballyPermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            _removeGloballyPermissionedContract(contracts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Gives the `contractAddress` permission to slash your funds.
    function allowToSlash(address contractAddress) external {
        _optIntoSlashing(msg.sender, contractAddress);        
    }
    /*
     TODO: we still need to figure out how/when to appropriately call this function
     perhaps a registry can safely call this function after an operator has been deregistered for a very safe amount of time (like a month)
    */
    /// @notice Called by a contract to revoke its ability to slash `operator`.
    function revokeSlashingAbility(address operator) external {
        _revokeSlashingAbility(operator, msg.sender);
    }

    /**
     * @notice Used for 'slashing' a certain operator.
     * @dev Technically the operator is 'frozen' (hence the name of this function), and then subject to slashing.
     * @param toBeFrozen The operator to be frozen.
     */
    function freezeOperator(
        address toBeFrozen
    ) external whenNotPaused {
        require(canSlash(toBeFrozen, msg.sender), "Slasher.freezeOperator: msg.sender does not have permission to slash this operator");
        _freezeOperator(toBeFrozen, msg.sender);
    }

    /// @notice Removes the 'frozen' status from all the `frozenAddresses`
    function resetFrozenStatus(address[] calldata frozenAddresses) external onlyOwner {
        for (uint256 i = 0; i < frozenAddresses.length; ) {
            _resetFrozenStatus(frozenAddresses[i]);
            unchecked { ++i; }
        }
    }

    // INTERNAL FUNCTIONS
    function _optIntoSlashing(address operator, address contractAddress) internal {
        if (!optedIntoSlashing[operator][contractAddress]) {
            optedIntoSlashing[operator][contractAddress] = true;
            emit OptedIntoSlashing(operator, contractAddress);        
        }
    }

    function _revokeSlashingAbility(address operator, address contractAddress) internal {
        if (optedIntoSlashing[operator][contractAddress]) {
            optedIntoSlashing[operator][contractAddress] = false;
            emit SlashingAbilityRevoked(operator, contractAddress);        
        }
    }

    function _addGloballyPermissionedContract(address contractToAdd) internal {
        if (!globallyPermissionedContracts[contractToAdd]) {
            globallyPermissionedContracts[contractToAdd] = true;
            emit GloballyPermissionedContractAdded(contractToAdd);
        }
    }

    function _removeGloballyPermissionedContract(address contractToRemove) internal {
        if (globallyPermissionedContracts[contractToRemove]) {
            globallyPermissionedContracts[contractToRemove] = false;
            emit GloballyPermissionedContractRemoved(contractToRemove);
        }
    }

    function _freezeOperator(address toBeFrozen, address slashingContract) internal {
        if (!frozenStatus[toBeFrozen]) {
            frozenStatus[toBeFrozen] = true;
            emit OperatorSlashed(toBeFrozen, slashingContract);
        }
    }

    function _resetFrozenStatus(address previouslySlashedAddress) internal {
        if (frozenStatus[previouslySlashedAddress]) {
            frozenStatus[previouslySlashedAddress] = false;
            emit FrozenStatusReset(previouslySlashedAddress);
        }
    }

    // VIEW FUNCTIONS
    /**
     * @notice Used to determine whether `staker` is actively 'frozen'.
     * @return Returns 'true' if `staker` themselves has their status set to frozen, OR if the staker is delegated
     * to an operator who has their status set to frozen. Otherwise returns 'false'.
     */
    function isFrozen(address staker) external view returns (bool) {
        if (frozenStatus[staker]) {
            return true;
        } else if (delegation.isDelegated(staker)) {
            address operatorAddress = delegation.delegation(staker);
            return(frozenStatus[operatorAddress]);
        } else {
            return false;
        }
    }

    /// @notice Checks if `slashingContract` is allowed to slash `toBeSlashed`.
    function canSlash(address toBeSlashed, address slashingContract) public view returns (bool) {
        if (globallyPermissionedContracts[slashingContract]) {
            return true;
        } else if (optedIntoSlashing[toBeSlashed][slashingContract]) {
            return true;
        } else {
            return false;
        }
    }
}
