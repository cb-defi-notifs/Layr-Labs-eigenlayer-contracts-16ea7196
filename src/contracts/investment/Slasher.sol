// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/IRepository.sol";
import "../interfaces/ISlasher.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentManager.sol";
import "../libraries/StructuredLinkedList.sol";
import "../permissions/Pausable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

import "forge-std/Test.sol";

/**
 * @title The primary 'slashing' contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice This contract specifies details on slashing. The functionalities are:
 * - adding contracts who have permission to perform slashing,
 * - revoking permission for slashing from specified contracts,
 * - calling investManager to do actual slashing.
 */
contract Slasher is Initializable, OwnableUpgradeable, ISlasher, Pausable {
    using StructuredLinkedList for StructuredLinkedList.List;
    /// @notice The central InvestmentManager contract of EigenLayr
    IInvestmentManager public investmentManager;
    /// @notice The EigenLayrDelegation contract of EigenLayr
    IEigenLayrDelegation public delegation;
    // contract address => whether or not the contract is allowed to slash any staker (or operator) in EigenLayr
    mapping(address => bool) public globallyPermissionedContracts;
    // user => contract => the time before which the contract is allowed to slash the user
    mapping(address => mapping(address => uint32)) public bondedUntil;
    // staker => if their funds are 'frozen' and potentially subject to slashing or not
    mapping(address => bool) public frozenStatus;

    uint32 internal constant MAX_BONDED_UNTIL = type(uint32).max;

    mapping(address => StructuredLinkedList.List) operatorToWhitelistedContractsByUpdate;
    mapping(address => mapping(address => uint32)) operatorToWhitelistedContractsToLatestUpdateTime;
    mapping(address => MiddlewareTimes[]) middlewareTimes;


    event GloballyPermissionedContractAdded(address indexed contractAdded);
    event GloballyPermissionedContractRemoved(address indexed contractRemoved);
    event OptedIntoSlashing(address indexed operator, address indexed contractAddress);
    event SlashingAbilityRevoked(address indexed operator, address indexed contractAddress, uint32 unbondedAfter);
    event OperatorSlashed(address indexed slashedOperator, address indexed slashingContract);
    event FrozenStatusReset(address indexed previouslySlashedAddress);

    constructor() {
        _disableInitializers();
    }

    // EXTERNAL FUNCTIONS
    function initialize(
        IInvestmentManager _investmentManager,
        IEigenLayrDelegation _delegation,
        IPauserRegistry _pauserRegistry,
        address _eigenLayrGovernance
    ) external initializer {
        _initializePauser(_pauserRegistry);
        investmentManager = _investmentManager;
        _addGloballyPermissionedContract(address(investmentManager));
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
    /// @notice Called by a contract to revoke its ability to slash `operator`, once `unbondedAfter` is reached.

    function revokeSlashingAbility(address operator, uint32 unbondedAfter) external {
        _revokeSlashingAbility(operator, msg.sender, unbondedAfter);
    }

    /**
     * @notice Used for 'slashing' a certain operator.
     * @dev Technically the operator is 'frozen' (hence the name of this function), and then subject to slashing.
     * @param toBeFrozen The operator to be frozen.
     */
    function freezeOperator(address toBeFrozen) external whenNotPaused {
        require(
            canSlash(toBeFrozen, msg.sender),
            "Slasher.freezeOperator: msg.sender does not have permission to slash this operator"
        );
        _freezeOperator(toBeFrozen, msg.sender);
    }

    /// @notice Removes the 'frozen' status from all the `frozenAddresses`
    function resetFrozenStatus(address[] calldata frozenAddresses) external onlyOwner {
        for (uint256 i = 0; i < frozenAddresses.length;) {
            _resetFrozenStatus(frozenAddresses[i]);
            unchecked {
                ++i;
            }
        }
    }

    // INTERNAL FUNCTIONS
    function _optIntoSlashing(address operator, address contractAddress) internal {
        //allow the contract to slash anytime before a time VERY far in the future
        bondedUntil[operator][contractAddress] = MAX_BONDED_UNTIL;
        emit OptedIntoSlashing(operator, contractAddress);
    }

    function _revokeSlashingAbility(address operator, address contractAddress, uint32 unbondedAfter) internal {
        if (bondedUntil[operator][contractAddress] == MAX_BONDED_UNTIL) {
            //contractAddress can now only slash operator before unbondedAfter
            bondedUntil[operator][contractAddress] = unbondedAfter;
            emit SlashingAbilityRevoked(operator, contractAddress, unbondedAfter);
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
     * @notice Used to determine whether `staker` is actively 'frozen'. If a staker is frozen, then they are potentially subject to
     * slashing of their funds, and cannot cannot deposit or withdraw from the investmentManager until the slashing process is completed
     * and the staker's status is reset (to 'unfrozen').
     * @return Returns 'true' if `staker` themselves has their status set to frozen, OR if the staker is delegated
     * to an operator who has their status set to frozen. Otherwise returns 'false'.
     */
    function isFrozen(address staker) external view returns (bool) {
        if (frozenStatus[staker]) {
            return true;
        } else if (delegation.isDelegated(staker)) {
            address operatorAddress = delegation.delegatedTo(staker);
            return (frozenStatus[operatorAddress]);
        } else {
            return false;
        }
    }

    /// @notice Checks if `slashingContract` is allowed to slash `toBeSlashed`.
    function canSlash(address toBeSlashed, address slashingContract) public view returns (bool) {
        if (globallyPermissionedContracts[slashingContract]) {
            return true;
        } else if (block.timestamp < bondedUntil[toBeSlashed][slashingContract]) {
            return true;
        } else {
            return false;
        }
    }

    function _recordUpdateAndAddToMiddlewareTimes(address operator, uint32 serveUntil) internal {
        //update latest update
        operatorToWhitelistedContractsToLatestUpdateTime[operator][msg.sender] = uint32(block.timestamp);
        //load current middleware times tip
        MiddlewareTimes memory curr = middlewareTimes[operator][middlewareTimes[operator].length - 1];
        MiddlewareTimes memory next = MiddlewareTimes({
            updateTime: uint32(block.timestamp),
            leastRecentUpdateTime: 0,
            // if the current middleware's serve until is later than the current recorded one, update the latestServeUntil
            latestServeUntil: serveUntil > curr.latestServeUntil ? serveUntil : curr.latestServeUntil
        });
        if(operatorToWhitelistedContractsByUpdate[operator].getHead() == addressToUint(msg.sender)) {
            //if the updated middleware was the earliest update, set it to the 2nd earliest update's update time
            (bool hasNext, uint256 nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(addressToUint(msg.sender));
            if(hasNext) {
                //if there is a next node, then set the lastestRecentUpdateTime to its recorded value
                next.leastRecentUpdateTime = operatorToWhitelistedContractsToLatestUpdateTime[operator][uintToAddress(nextNode)];
            } else {
                //otherwise this is the only middleware so right now is the lastestRecentUpdateTime
                next.leastRecentUpdateTime = uint32(block.timestamp);
            }
        } else {
            //otherwise keep it the same
            next.leastRecentUpdateTime = curr.leastRecentUpdateTime;
        }
    }

    function addressToUint(address addr) internal pure returns(uint256) {
        return uint256(uint160(addr));
    }

    function uintToAddress(uint256 x) internal pure returns(address) {
        return address(uint160(x));
    }
}
