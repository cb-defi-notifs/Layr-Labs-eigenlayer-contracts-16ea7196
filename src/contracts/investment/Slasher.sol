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
 * - tracking historic stake updates to ensure that withdrawals can only be completed once no middlewares have slashing rights
 * over the funds being withdrawn
 */
contract Slasher is Initializable, OwnableUpgradeable, ISlasher, Pausable, DSTest {
    using StructuredLinkedList for StructuredLinkedList.List;

    uint256 private constant HEAD = 0;

    /// @notice The central InvestmentManager contract of EigenLayr
    IInvestmentManager public immutable investmentManager;
    /// @notice The EigenLayrDelegation contract of EigenLayr
    IEigenLayrDelegation public immutable delegation;
    // contract address => whether or not the contract is allowed to slash any staker (or operator) in EigenLayr
    mapping(address => bool) public globallyPermissionedContracts;
    // user => contract => the time before which the contract is allowed to slash the user
    mapping(address => mapping(address => uint32)) public bondedUntil;
    // staker => if their funds are 'frozen' and potentially subject to slashing or not
    mapping(address => bool) internal frozenStatus;

    uint32 internal constant MAX_BONDED_UNTIL = type(uint32).max;

    /**
     * operator => a linked list of the addresses of the whitelisted middleware with permission to slash the operator, i.e. which  
     * the operator is serving. Sorted by the block at which they were last updated (content of updates below) in ascending order.
     * This means the 'HEAD' (i.e. start) of the linked list will have the stalest 'updateBlock' value.
     */
    mapping(address => StructuredLinkedList.List) operatorToWhitelistedContractsByUpdate;
    //operator => whitelisted middleware slashing => block it was last updated
    mapping(address => mapping(address => uint32)) operatorToWhitelistedContractsToLatestUpdateBlock;
    /**
     * operator => 
     *  [
     *      (
     *          the least recent update block of all of the middlewares it's serving/served, 
     *          latest time the the stake bonded at that update needed to serve until
     *      )
     *  ]
     */
    mapping(address => MiddlewareTimes[]) public operatorToMiddlewareTimes;

    /// @notice Emitted when `contractAdded` is added to the list of globallyPermissionedContracts.
    event GloballyPermissionedContractAdded(address indexed contractAdded);

    /// @notice Emitted when `contractRemoved` is removed from the list of globallyPermissionedContracts.
    event GloballyPermissionedContractRemoved(address indexed contractRemoved);

    /// @notice Emitted when `operator` begins to allow `contractAddress` to slash them.
    event OptedIntoSlashing(address indexed operator, address indexed contractAddress);

    /// @notice Emitted when `contractAddress` signals that it will no longer be able to slash `operator` after the UTC timestamp `unbondedAfter.
    event SlashingAbilityRevoked(address indexed operator, address indexed contractAddress, uint32 unbondedAfter);

    /**
     * @notice Emitted when `slashingContract` 'slashes' (technically, 'freezes') the `slashedOperator`.
     * @dev The `slashingContract` must have permission to slash the `slashedOperator`, i.e. `canSlash(slasherOperator, slashingContract)` must return 'true'.
     */
    event OperatorSlashed(address indexed slashedOperator, address indexed slashingContract);

    /// @notice Emitted when `previouslySlashedAddress` is 'unfrozen', allowing them to again move deposited funds within EigenLayer.
    event FrozenStatusReset(address indexed previouslySlashedAddress);

    constructor(IInvestmentManager _investmentManager, IEigenLayrDelegation _delegation) {
        investmentManager = _investmentManager;
        delegation = _delegation;
        _disableInitializers();
    }

    /// @notice Ensures that the caller is allowed to slash the operator.
    modifier onlyCanSlash(address operator) {
        require(canSlash(operator, msg.sender), "Slasher.onlyCanSlash: only slashing contracts");
        _;
    }

    // EXTERNAL FUNCTIONS
    function initialize(
        IPauserRegistry _pauserRegistry,
        address initialOwner
    ) external initializer {
        _initializePauser(_pauserRegistry);
        _transferOwnership(initialOwner);
        // add InvestmentManager & EigenLayrDelegation to list of permissioned contracts
        _addGloballyPermissionedContract(address(investmentManager));
        _addGloballyPermissionedContract(address(delegation));
    }

    /**
     * @notice Gives the `contractAddress` permission to slash the funds of the caller.
     * @dev Typically, this function must be called prior to registering for a middleware.
     */
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
     * @param toBeFrozen The operator to be frozen.
     * @dev Technically the operator is 'frozen' (hence the name of this function), and then subject to slashing pending a decision by a human-in-the-loop.
     * @dev The operator must have previously given the caller (which should be a contract) the ability to slash them, through a call to `allowToSlash`.
     */
    function freezeOperator(address toBeFrozen) external whenNotPaused {
        require(
            canSlash(toBeFrozen, msg.sender),
            "Slasher.freezeOperator: msg.sender does not have permission to slash this operator"
        );
        _freezeOperator(toBeFrozen, msg.sender);
    }

    /**
     * @notice Used to give global slashing permission to `contracts`.
     * @dev Callable only by the contract owner (i.e. governance).
     */
    function addGloballyPermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            _addGloballyPermissionedContract(contracts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Used to revoke global slashing permission from `contracts`.
     * @dev Callable only by the contract owner (i.e. governance).
     */
    function removeGloballyPermissionedContracts(address[] calldata contracts) external onlyOwner {
        for (uint256 i = 0; i < contracts.length;) {
            _removeGloballyPermissionedContract(contracts[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Removes the 'frozen' status from each of the `frozenAddresses`
     * @dev Callable only by the contract owner (i.e. governance).
     */
    function resetFrozenStatus(address[] calldata frozenAddresses) external onlyOwner {
        for (uint256 i = 0; i < frozenAddresses.length;) {
            _resetFrozenStatus(frozenAddresses[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice this function is a called by middlewares during an operator's registration to make sure the operator's stake at registration 
     *         is slashable until serveUntil
     * @param operator the operator whose stake update is being recorded
     * @param serveUntil the timestamp until which the operator's stake at the current block is slashable
     * @dev adds the middleware's slashing contract to the operator's linked list
     */
    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {

        // update latest update

        _recordUpdateAndAddToMiddlewareTimes(operator, uint32(block.number), serveUntil);

        // Push the middleware to the end of the update list. This will fail if the caller *is* already in the list.
        require(operatorToWhitelistedContractsByUpdate[operator].pushBack(addressToUint(msg.sender)), 
            "Slasher.recordFirstStakeUpdate: Appending middleware unsuccessful");
    }

    /**
     * @notice this function is a called by middlewares during a stake update for an operator (perhaps to free pending withdrawals)
     *         to make sure the operator's stake at updateBlock is slashable until serveUntil
     * @param operator the operator whose stake update is being recorded
     * @param updateBlock the block for which the stake update is being recorded
     * @param serveUntil the timestamp until which the operator's stake at updateBlock is slashable
     * @param insertAfter the element of the operators linked list that the currently updating middleware should be inserted after
     * @dev insertAfter should be calculated offchain before making the transaction that calls this. this is subject to race conditions, 
     *      but it is anticipated to be rare and not detrimental.
     */
    function recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 insertAfter) 
        external 
        onlyCanSlash(operator) 
    {
        // sanity check on input
        require(updateBlock <= block.number, "Slasher.recordStakeUpdate: cannot provide update for future block");
        // update the 'stalest' stakes update time + latest 'serveUntil' time of the `operator`
        _recordUpdateAndAddToMiddlewareTimes(operator, updateBlock, serveUntil);

        /**
         * Move the middleware to its correct update position, determined by `updateBlock` and indicated via `insertAfter`.
         * If the the middleware is the only one in the list, then no need to mutate the list
         */
        if (operatorToWhitelistedContractsByUpdate[operator].sizeOf() != 1) {
            // Remove the caller (middleware) from the list. This will fail if the caller is *not* already in the list.
            require(operatorToWhitelistedContractsByUpdate[operator].remove(addressToUint(msg.sender)) != 0, 
                "Slasher.recordStakeUpdate: Removing middleware unsuccessful");
            // Run routine for updating the `operator`'s linked list of middlewares
            _updateMiddlewareList(operator, updateBlock, insertAfter);
        }
    }

    /**
     * @notice this function is a called by middlewares during an operator's deregistration to make sure the operator's stake at deregistration 
     *         is slashable until serveUntil
     * @param operator the operator whose stake update is being recorded
     * @param serveUntil the timestamp until which the operator's stake at the current block is slashable
     * @dev removes the middleware's slashing contract to the operator's linked list
     */
    function recordLastStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {
        // update the 'stalest' stakes update time + latest 'serveUntil' time of the `operator`
        _recordUpdateAndAddToMiddlewareTimes(operator, uint32(block.number), serveUntil);
        //remove the middleware from the list
        require(operatorToWhitelistedContractsByUpdate[operator].remove(addressToUint(msg.sender)) != 0,
             "Slasher.recordLastStakeUpdate: Removing middleware unsuccessful");
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

    /// @notice Returns true if `slashingContract` is currently allowed to slash `toBeSlashed`.
    function canSlash(address toBeSlashed, address slashingContract) public view returns (bool) {
        if (globallyPermissionedContracts[slashingContract]) {
            return true;
        } else if (block.timestamp < bondedUntil[toBeSlashed][slashingContract]) {
            return true;
        } else {
            return false;
        }
    }

    /**
     * @notice Returns 'true' if `operator` can currently complete a withdrawal started at the `withdrawalStartBlock`, with `middlewareTimesIndex` used
     * to specify the index of a `MiddlewareTimes` struct in the operator's list (i.e. an index in `operatorToMiddlewareTimes[operator]`). The specified
     * struct is consulted as proof of the `operator`'s ability (or lack thereof) to complete the withdrawal.
     * This function will return 'false' if the operator cannot currently complete a withdrawal started at the `withdrawalStartBlock`, *or* in the event
     * that an incorrect `middlewareTimesIndex` is supplied, even if one or more correct inputs exist.
     * @param operator Either the operator who queued the withdrawal themselves, or if the withdrawing party is a staker who delegated to an operator,
     * this address is the operator *who the staker was delegated to* at the time of the `withdrawalStartBlock`.
     * @param withdrawalStartBlock The block number at which the withdrawal was initiated.
     * @param middlewareTimesIndex Indicates an index in `operatorToMiddlewareTimes[operator]` to consult as proof of the `operator`'s ability to withdraw
     * @dev The correct `middlewareTimesIndex` input should be computable off-chain.
     */
    function canWithdraw(address operator, uint32 withdrawalStartBlock, uint256 middlewareTimesIndex) external view returns(bool) {
        if (operatorToMiddlewareTimes[operator].length == 0) {
            return true;
        }
        //make sure earliest update block at the time is after withdrawalStartBlock
        //make sure the current time is after the latestServeUntil at the time
        //this assures us that this that
        //all middlewares were updated after the withdrawal and
        //the stake is no longer slashable
        MiddlewareTimes memory update = operatorToMiddlewareTimes[operator][middlewareTimesIndex];
        
        // emit log("withdrawalStartBlock < update.leastRecentUpdateBlock");
        // emit log_named_uint("withdrawalStartBlock", withdrawalStartBlock);
        // emit log_named_uint("update.leastRecentUpdateBlock ", update.leastRecentUpdateBlock );

        // emit log("uint32(block.timestamp) > update.latestServeUntil");
        // emit log_named_uint("uint32(block.timestamp)", uint32(block.timestamp));
        // emit log_named_uint("update.latestServeUntil", update.latestServeUntil);

        return(
            withdrawalStartBlock < update.leastRecentUpdateBlock 
            &&
            uint32(block.timestamp) > update.latestServeUntil
        );
    }

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].leastRecentUpdateBlock`.
    function getMiddlewareTimesIndexBlock(address operator, uint32 index) external view returns(uint32){
        return operatorToMiddlewareTimes[operator][index].leastRecentUpdateBlock;
    }

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].latestServeUntil`.
    function getMiddlewareTimesIndexServeUntil(address operator, uint32 index) external view returns(uint32) {
        return operatorToMiddlewareTimes[operator][index].latestServeUntil;
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

    /**
     * @notice records the most recent updateBlock for the currently updating middleware and appends an entry to the operator's list of 
     *         MiddlewareTimes if relavent information has updated
     * @param operator the entity whose stake update is being recorded
     * @param updateBlock the block number for which the currently updating middleware is updating the serveUntil for
     * @param serveUntil the timestamp until which the operator's stake at updateBlock is slashable
     * @dev this function is only called during externally called stake updates by middleware contracts that can slash operator
     */
    function _recordUpdateAndAddToMiddlewareTimes(address operator, uint32 updateBlock, uint32 serveUntil) internal {
        // reject any stale update, i.e. one from before that of the most recent recorded update for the currently updating middleware
        require(operatorToWhitelistedContractsToLatestUpdateBlock[operator][msg.sender] <= updateBlock, 
                "Slasher._recordUpdateAndAddToMiddlewareTimes: can't push a previous update");
        operatorToWhitelistedContractsToLatestUpdateBlock[operator][msg.sender] = updateBlock;
        // get the latest recorded MiddlewareTimes, if the operator's list of MiddlwareTimes is non empty
        MiddlewareTimes memory curr;
        if(operatorToMiddlewareTimes[operator].length != 0) {
            curr = operatorToMiddlewareTimes[operator][operatorToMiddlewareTimes[operator].length - 1];
        }
        MiddlewareTimes memory next = curr;
        bool pushToMiddlewareTimes;
        // if the serve until is later than the latest recorded one, update it
        if(serveUntil > curr.latestServeUntil) {
            next.latestServeUntil = serveUntil;
            // mark that we need push next to middleware times array because it contains new information
            pushToMiddlewareTimes = true;
        } 
        
        // If this is the very first middleware added to the operator's list of middlewware, then we add an entry to operatorToMiddlewareTimes
        if (operatorToWhitelistedContractsByUpdate[operator].size == 0) {
            pushToMiddlewareTimes = true;
            next.leastRecentUpdateBlock = updateBlock;
        }
        // If the middleware is the first in the list, we will update the `leastRecentUpdateBlock` field in MiddlwareTimes
        else if (operatorToWhitelistedContractsByUpdate[operator].getHead() == addressToUint(msg.sender)) {
            // if the updated middleware was the earliest update, set it to the 2nd earliest update's update time
            (bool hasNext, uint256 nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(addressToUint(msg.sender));

            if(hasNext) {
                // get the next middleware's most latest update block
                uint32 nextMiddlewaresLeastRecentUpdateBlock = operatorToWhitelistedContractsToLatestUpdateBlock[operator][uintToAddress(nextNode)];
                if(nextMiddlewaresLeastRecentUpdateBlock < updateBlock) {
                    // if there is a next node, then set the leastRecentUpdateBlock to its recorded value
                    next.leastRecentUpdateBlock = nextMiddlewaresLeastRecentUpdateBlock;
                } else {
                    //otherwise updateBlock is the least recent update as well
                    next.leastRecentUpdateBlock = updateBlock;
                }
            } else {
                // otherwise this is the only middleware so right now is the leastRecentUpdateBlock
                next.leastRecentUpdateBlock = updateBlock;
            }
            // mark that we need push next to middleware times array because it contains new information
            pushToMiddlewareTimes = true;
        }
        
        // if next has new information, push it
        if(pushToMiddlewareTimes) {
            operatorToMiddlewareTimes[operator].push(next);
        }
        // emit log("____________________________________________");
        // emit log_named_uint("next.latestServeUntil", next.latestServeUntil);
        // emit log_named_uint("next.leastRecentUpdateBlock", next.leastRecentUpdateBlock);
        // emit log_named_uint("updateBlock", updateBlock);
        // emit log("____________________________________________");

    }

    /// @notice A routine for updating the `operator`'s linked list of middlewares, inside `recordStakeUpdate`.
    function _updateMiddlewareList(address operator, uint32 updateBlock, uint256 insertAfter) internal {
        /**
         * boolean used to track if the `insertAfter input to this function is incorrect. If it is, then `runFallbackRoutine` will
         * be flipped to 'true', and we will use `_getCorrectValueForInsertAfter` to find the correct input. This routine helps solve
         * a race condition where the proper value of `insertAfter` changes while a transaction is pending.
         */
        bool runFallbackRoutine = false;
        // If this condition is met, then the `updateBlock` input should be after `insertAfter`'s latest updateBlock
        if (insertAfter != HEAD) {
            // Check that `insertAfter` exists. If not, we will use the fallback routine to find the correct value for `insertAfter`.
            if (!operatorToWhitelistedContractsByUpdate[operator].nodeExists(insertAfter)) {
                runFallbackRoutine = true;
            }

            /**
             * Make sure `insertAfter` specifies a node for which the most recent updateBlock was *at or before* updateBlock.
             * Again, if not,  we will use the fallback routine to find the correct value for `insertAfter`.
             */
            if ((!runFallbackRoutine) && (operatorToWhitelistedContractsToLatestUpdateBlock[operator][uintToAddress(insertAfter)] > updateBlock)) {
                runFallbackRoutine = true;
            }

            // if we have not marked `runFallbackRoutine` as 'true' yet, then that means the `insertAfter` input was correct so far
            if (!runFallbackRoutine) {
                // Get `insertAfter`'s successor. `hasNext` will be false if `insertAfter` is the last node in the list
                (bool hasNext, uint256 nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(insertAfter);
                if (hasNext) {
                    /**
                     * Make sure the element after `insertAfter`'s most recent updateBlock was *strictly after* `updateBlock`.
                     * Again, if not,  we will use the fallback routine to find the correct value for `insertAfter`.
                     */
                    if (operatorToWhitelistedContractsToLatestUpdateBlock[operator][uintToAddress(nextNode)] <= updateBlock) {
                        runFallbackRoutine = true;
                    }
                }
            }

            // if we have not marked `runFallbackRoutine` as 'true' yet, then that means the `insertAfter` input was correct on all counts
            if (!runFallbackRoutine) {
                /** 
                 * Insert the caller (middleware) after `insertAfter`.
                 * This will fail if `msg.sender` is already in the list, which they shouldn't be because they were removed from the list above.
                 */
                require(operatorToWhitelistedContractsByUpdate[operator].insertAfter(insertAfter, addressToUint(msg.sender)),
                    "Slasher.recordStakeUpdate: Inserting middleware unsuccessful");
            // in this case (runFallbackRoutine == true), we run a search routine to find the correct input value of `insertAfter` and then rerun this function
            } else {
                insertAfter = _getCorrectValueForInsertAfter(operator, updateBlock);
                _updateMiddlewareList(operator, updateBlock, insertAfter);
            }
        // In this case (insertAfter == HEAD), the `updateBlock` input should be before every other middleware's latest updateBlock.
        } else {
            /**
             * Check that `updateBlock` is before any other middleware's latest updateBlock.
             * If not, use the fallback routine to find the correct value for `insertAfter`.
             */
            if (operatorToWhitelistedContractsToLatestUpdateBlock[operator][
                uintToAddress(operatorToWhitelistedContractsByUpdate[operator].getHead()) ] <= updateBlock)
            {
                runFallbackRoutine = true;
            }
            // if we have not marked `runFallbackRoutine` as 'true' yet, then that means the `insertAfter` input was correct on all counts
            if (!runFallbackRoutine) {
                /**
                 * Insert the middleware at the start (i.e. HEAD) of the list.
                 * This will fail if `msg.sender` is already in the list, which they shouldn't be because they were removed from the list above.
                 */
                require(operatorToWhitelistedContractsByUpdate[operator].pushFront(addressToUint(msg.sender)), 
                    "Slasher.recordStakeUpdate: Preppending middleware unsuccessful");
            // in this case (runFallbackRoutine == true), we run a search routine to find the correct input value of `insertAfter` and then rerun this function
            } else {
                insertAfter = _getCorrectValueForInsertAfter(operator, updateBlock);
                _updateMiddlewareList(operator, updateBlock, insertAfter);
            }
        }
    }

    /**
     * @notice A search routine for finding the correct input value of `insertAfter` to `_updateMiddlewareList`.
     * @dev Used within this contract only as a fallback in the case when an incorrect value of `insertAfter` is supplied as an input to `_updateMiddlewareList`.
     * @dev The return value should *either* be 'HEAD' (i.e. zero) in the event that the node being inserted in the linked list has an `updateBlock`
     * that is less than the HEAD of the list, *or* the return value should specify the last `node` in the linked list for which
     * `operatorToWhitelistedContractsToLatestUpdateBlock[operator][node] <= updateBlock`, i.e. the node such that the *next* node either doesn't exist, or
     * `operatorToWhitelistedContractsToLatestUpdateBlock[operator][nextNode] > updateBlock`.
     */
    function _getCorrectValueForInsertAfter(address operator, uint32 updateBlock) internal view returns (uint256) {
        uint256 node = operatorToWhitelistedContractsByUpdate[operator].getHead();
        /**
         * Special case:
         * If the node being inserted in the linked list has an `updateBlock` that is less than the HEAD of the list, then we set `insertAfter = HEAD`.
         * In _updateMiddlewareList(), the new node will be pushed to the front (HEAD) of the list.
         */
        if (operatorToWhitelistedContractsToLatestUpdateBlock[operator][uintToAddress(node)] > updateBlock) {
            return HEAD;
        }
        /**
         * `node` being zero (i.e. equal to 'HEAD') indicates an empty/non-existent node, i.e. reaching the end of the linked list.
         * Since the linked list is ordered in ascending order of update blocks, we simply start from the head of the list and step through until
         * we find a the *last* `node` for which `operatorToWhitelistedContractsToLatestUpdateBlock[operator][node] <= updateBlock`, or
         * otherwise reach the end of the list.
         */
        (, uint256 nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(node);
        while ((nextNode != HEAD) && (operatorToWhitelistedContractsToLatestUpdateBlock[operator][uintToAddress(node)] <= updateBlock)) {
            (, nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(node);
            node = nextNode;
        }
        return node;
    }

    function addressToUint(address addr) internal pure returns(uint256) {
        return uint256(uint160(addr));
    }

    function uintToAddress(uint256 x) internal pure returns(address) {
        return address(uint160(x));
    }    
}
