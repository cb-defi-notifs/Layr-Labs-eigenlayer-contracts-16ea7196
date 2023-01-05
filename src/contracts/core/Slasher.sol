// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "../interfaces/ISlasher.sol";
import "../interfaces/IEigenLayrDelegation.sol";
import "../interfaces/IInvestmentManager.sol";
import "../libraries/StructuredLinkedList.sol";
import "../permissions/Pausable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";

// import "forge-std/Test.sol";

/**
 * @title The primary 'slashing' contract for EigenLayr.
 * @author Layr Labs, Inc.
 * @notice This contract specifies details on slashing. The functionalities are:
 * - adding contracts who have permission to perform slashing,
 * - revoking permission for slashing from specified contracts,
 * - tracking historic stake updates to ensure that withdrawals can only be completed once no middlewares have slashing rights
 * over the funds being withdrawn
 */
contract Slasher is Initializable, OwnableUpgradeable, ISlasher, Pausable {
    using StructuredLinkedList for StructuredLinkedList.List;

    uint256 private constant HEAD = 0;

    uint8 internal constant PAUSED_OPT_INTO_SLASHING = 0;
    uint8 internal constant PAUSED_FIRST_STAKE_UPDATE = 1;
    uint8 internal constant PAUSED_NEW_FREEZING = 2;

    /// @notice The central InvestmentManager contract of EigenLayr
    IInvestmentManager public immutable investmentManager;
    /// @notice The EigenLayrDelegation contract of EigenLayr
    IEigenLayrDelegation public immutable delegation;
    // operator => whitelisted contract with slashing permissions => (the time before which the contract is allowed to slash the user, block it was last updated)
    mapping(address => mapping(address => MiddlewareDetails)) internal _whitelistedContractDetails;
    // staker => if their funds are 'frozen' and potentially subject to slashing or not
    mapping(address => bool) internal frozenStatus;

    uint32 internal constant MAX_BONDED_UNTIL = type(uint32).max;

    /**
     * operator => a linked list of the addresses of the whitelisted middleware with permission to slash the operator, i.e. which  
     * the operator is serving. Sorted by the block at which they were last updated (content of updates below) in ascending order.
     * This means the 'HEAD' (i.e. start) of the linked list will have the stalest 'updateBlock' value.
     */
    mapping(address => StructuredLinkedList.List) public operatorToWhitelistedContractsByUpdate;
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

    /// @notice Emitted when `operator` begins to allow `contractAddress` to slash them.
    event OptedIntoSlashing(address indexed operator, address indexed contractAddress);

    /// @notice Emitted when `contractAddress` signals that it will no longer be able to slash `operator` after the UTC timestamp `bondedUntil.
    event SlashingAbilityRevoked(address indexed operator, address indexed contractAddress, uint32 bondedUntil);

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
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _transferOwnership(initialOwner);
    }

    /**
     * @notice Gives the `contractAddress` permission to slash the funds of the caller.
     * @dev Typically, this function must be called prior to registering for a middleware.
     */
    function optIntoSlashing(address contractAddress) external onlyWhenNotPaused(PAUSED_OPT_INTO_SLASHING) {
        require(delegation.isOperator(msg.sender), "Slasher.optIntoSlashing: msg.sender is not a registered operator");
        _optIntoSlashing(msg.sender, contractAddress);
    }

    /**
     * @notice Used for 'slashing' a certain operator.
     * @param toBeFrozen The operator to be frozen.
     * @dev Technically the operator is 'frozen' (hence the name of this function), and then subject to slashing pending a decision by a human-in-the-loop.
     * @dev The operator must have previously given the caller (which should be a contract) the ability to slash them, through a call to `optIntoSlashing`.
     */
    function freezeOperator(address toBeFrozen) external onlyWhenNotPaused(PAUSED_NEW_FREEZING) {
        require(
            canSlash(toBeFrozen, msg.sender),
            "Slasher.freezeOperator: msg.sender does not have permission to slash this operator"
        );
        _freezeOperator(toBeFrozen, msg.sender);
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
    function recordFirstStakeUpdate(address operator, uint32 serveUntil) 
        external 
        onlyWhenNotPaused(PAUSED_FIRST_STAKE_UPDATE)
        onlyCanSlash(operator) 
    {

        // update latest update

        _recordUpdateAndAddToMiddlewareTimes(operator, uint32(block.number), serveUntil);


        // Push the middleware to the end of the update list. This will fail if the caller *is* already in the list.
        require(operatorToWhitelistedContractsByUpdate[operator].pushBack(_addressToUint(msg.sender)), 
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
            require(operatorToWhitelistedContractsByUpdate[operator].remove(_addressToUint(msg.sender)) != 0, 
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
     * @dev removes the middleware's slashing contract to the operator's linked list and revokes the middleware's (i.e. caller's) ability to
     * slash `operator` once `serveUntil` is reached
     */
    function recordLastStakeUpdateAndRevokeSlashingAbility(address operator, uint32 serveUntil) external onlyCanSlash(operator) {
        // update the 'stalest' stakes update time + latest 'serveUntil' time of the `operator`
        _recordUpdateAndAddToMiddlewareTimes(operator, uint32(block.number), serveUntil);
        // remove the middleware from the list
        require(operatorToWhitelistedContractsByUpdate[operator].remove(_addressToUint(msg.sender)) != 0,
             "Slasher.recordLastStakeUpdateAndRevokeSlashingAbility: Removing middleware unsuccessful");
        // revoke the middleware's ability to slash `operator` after `serverUntil`
        _revokeSlashingAbility(operator, msg.sender, serveUntil);
    }

    // VIEW FUNCTIONS

    /// @notice Returns the UTC timestamp until which `serviceContract` is allowed to slash the `operator`.
    function bondedUntil(address operator, address serviceContract) external view returns (uint32) {
        return _whitelistedContractDetails[operator][serviceContract].bondedUntil;
    }

    /// @notice Returns the block at which the `serviceContract` last updated its view of the `operator`'s stake
    function latestUpdateBlock(address operator, address serviceContract) external view returns (uint32) {
        return _whitelistedContractDetails[operator][serviceContract].latestUpdateBlock;
    }

    /*
    * @notice Returns `_whitelistedContractDetails[operator][serviceContract]`.
    * @dev A getter function like this appears to be necessary for returning a struct from storage
    */
    function whitelistedContractDetails(address operator, address serviceContract) external view returns (MiddlewareDetails memory) {
        return _whitelistedContractDetails[operator][serviceContract];
    }


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
        if (block.timestamp < _whitelistedContractDetails[toBeSlashed][slashingContract].bondedUntil) {
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
    function canWithdraw(address operator, uint32 withdrawalStartBlock, uint256 middlewareTimesIndex) external view returns (bool) {
        // if the operator has never registered for a middleware, just return 'true'
        if (operatorToMiddlewareTimes[operator].length == 0) {
            return true;
        }

        // pull the MiddlewareTimes struct at the `middlewareTimesIndex`th position in `operatorToMiddlewareTimes[operator]`
        MiddlewareTimes memory update = operatorToMiddlewareTimes[operator][middlewareTimesIndex];
        
        /**
         * Make sure the stalest update block at the time of the update is strictly after `withdrawalStartBlock` and ensure that the current time
         * is after the `latestServeUntil` of the update. This assures us that this that all middlewares were updated after the withdrawal began, and
         * that the stake is no longer slashable.
         */
        return(
            withdrawalStartBlock < update.stalestUpdateBlock 
            &&
            uint32(block.timestamp) > update.latestServeUntil
        );
    }

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].stalestUpdateBlock`.
    function getMiddlewareTimesIndexBlock(address operator, uint32 index) external view returns (uint32){
        return operatorToMiddlewareTimes[operator][index].stalestUpdateBlock;
    }

    /// @notice Getter function for fetching `operatorToMiddlewareTimes[operator][index].latestServeUntil`.
    function getMiddlewareTimesIndexServeUntil(address operator, uint32 index) external view returns (uint32) {
        return operatorToMiddlewareTimes[operator][index].latestServeUntil;
    }

    /**
     * @notice A search routine for finding the correct input value of `insertAfter` to `recordStakeUpdate` / `_updateMiddlewareList`.
     * @dev Used within this contract only as a fallback in the case when an incorrect value of `insertAfter` is supplied as an input to `_updateMiddlewareList`.
     * @dev The return value should *either* be 'HEAD' (i.e. zero) in the event that the node being inserted in the linked list has an `updateBlock`
     * that is less than the HEAD of the list, *or* the return value should specify the last `node` in the linked list for which
     * `_whitelistedContractDetails[operator][node].latestUpdateBlock <= updateBlock`,
     * i.e. the node such that the *next* node either doesn't exist,
     * OR
     * `_whitelistedContractDetails[operator][nextNode].latestUpdateBlock > updateBlock`.
     */
    function getCorrectValueForInsertAfter(address operator, uint32 updateBlock) public view returns (uint256) {
        uint256 node = operatorToWhitelistedContractsByUpdate[operator].getHead();
        /**
         * Special case:
         * If the node being inserted in the linked list has an `updateBlock` that is less than the HEAD of the list, then we set `insertAfter = HEAD`.
         * In _updateMiddlewareList(), the new node will be pushed to the front (HEAD) of the list.
         */
        if (_whitelistedContractDetails[operator][_uintToAddress(node)].latestUpdateBlock > updateBlock) {
            return HEAD;
        }
        /**
         * `node` being zero (i.e. equal to 'HEAD') indicates an empty/non-existent node, i.e. reaching the end of the linked list.
         * Since the linked list is ordered in ascending order of update blocks, we simply start from the head of the list and step through until
         * we find a the *last* `node` for which `_whitelistedContractDetails[operator][node] <= updateBlock`, or
         * otherwise reach the end of the list.
         */
        (, uint256 nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(node);
        while ((nextNode != HEAD) && (_whitelistedContractDetails[operator][_uintToAddress(node)].latestUpdateBlock <= updateBlock)) {
            (, nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(node);
            node = nextNode;
        }
        return node;
    }

    /// @notice gets the node previous to the given node in the operators middleware update linked list
    /// @dev used in offchain libs for updating stakes
    function getPreviousWhitelistedContractByUpdate(address operator, uint256 node) public view returns (bool, uint256) {
        return operatorToWhitelistedContractsByUpdate[operator].getPreviousNode(node);
    }

    // INTERNAL FUNCTIONS

    function _optIntoSlashing(address operator, address contractAddress) internal {
        //allow the contract to slash anytime before a time VERY far in the future
        _whitelistedContractDetails[operator][contractAddress].bondedUntil = MAX_BONDED_UNTIL;
        emit OptedIntoSlashing(operator, contractAddress);
    }

    function _revokeSlashingAbility(address operator, address contractAddress, uint32 serveUntil) internal {
        if (_whitelistedContractDetails[operator][contractAddress].bondedUntil == MAX_BONDED_UNTIL) {
            // contractAddress can now only slash operator before `serveUntil`
            _whitelistedContractDetails[operator][contractAddress].bondedUntil = serveUntil;
            emit SlashingAbilityRevoked(operator, contractAddress, serveUntil);
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
        require(_whitelistedContractDetails[operator][msg.sender].latestUpdateBlock <= updateBlock, 
                "Slasher._recordUpdateAndAddToMiddlewareTimes: can't push a previous update");
        _whitelistedContractDetails[operator][msg.sender].latestUpdateBlock = updateBlock;
        // get the latest recorded MiddlewareTimes, if the operator's list of MiddlwareTimes is non empty
        MiddlewareTimes memory curr;
        if (operatorToMiddlewareTimes[operator].length != 0) {
            curr = operatorToMiddlewareTimes[operator][operatorToMiddlewareTimes[operator].length - 1];
        }
        MiddlewareTimes memory next = curr;
        bool pushToMiddlewareTimes;
        // if the serve until is later than the latest recorded one, update it
        if (serveUntil > curr.latestServeUntil) {
            next.latestServeUntil = serveUntil;
            // mark that we need push next to middleware times array because it contains new information
            pushToMiddlewareTimes = true;
        } 
        
        // If this is the very first middleware added to the operator's list of middleware, then we add an entry to operatorToMiddlewareTimes
        if (operatorToWhitelistedContractsByUpdate[operator].size == 0) {
            pushToMiddlewareTimes = true;
            next.stalestUpdateBlock = updateBlock;
        }
        // If the middleware is the first in the list, we will update the `stalestUpdateBlock` field in MiddlwareTimes
        else if (operatorToWhitelistedContractsByUpdate[operator].getHead() == _addressToUint(msg.sender)) {
            // if the updated middleware was the earliest update, set it to the 2nd earliest update's update time
            (bool hasNext, uint256 nextNode) = operatorToWhitelistedContractsByUpdate[operator].getNextNode(_addressToUint(msg.sender));

            if(hasNext) {
                // get the next middleware's most latest update block
                uint32 nextMiddlewaresLeastRecentUpdateBlock = _whitelistedContractDetails[operator][_uintToAddress(nextNode)].latestUpdateBlock;
                if(nextMiddlewaresLeastRecentUpdateBlock < updateBlock) {
                    // if there is a next node, then set the stalestUpdateBlock to its recorded value
                    next.stalestUpdateBlock = nextMiddlewaresLeastRecentUpdateBlock;
                } else {
                    //otherwise updateBlock is the least recent update as well
                    next.stalestUpdateBlock = updateBlock;
                }
            } else {
                // otherwise this is the only middleware so right now is the stalestUpdateBlock
                next.stalestUpdateBlock = updateBlock;
            }
            // mark that we need push next to middleware times array because it contains new information
            pushToMiddlewareTimes = true;
        }
        
        // if `next` has new information, then push it
        if (pushToMiddlewareTimes) {
            operatorToMiddlewareTimes[operator].push(next);
        }
    }

    /// @notice A routine for updating the `operator`'s linked list of middlewares, inside `recordStakeUpdate`.
    function _updateMiddlewareList(address operator, uint32 updateBlock, uint256 insertAfter) internal {
        /**
         * boolean used to track if the `insertAfter input to this function is incorrect. If it is, then `runFallbackRoutine` will
         * be flipped to 'true', and we will use `getCorrectValueForInsertAfter` to find the correct input. This routine helps solve
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
            if ((!runFallbackRoutine) && (_whitelistedContractDetails[operator][_uintToAddress(insertAfter)].latestUpdateBlock > updateBlock)) {
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
                    if (_whitelistedContractDetails[operator][_uintToAddress(nextNode)].latestUpdateBlock <= updateBlock) {
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
                require(operatorToWhitelistedContractsByUpdate[operator].insertAfter(insertAfter, _addressToUint(msg.sender)),
                    "Slasher.recordStakeUpdate: Inserting middleware unsuccessful");
            // in this case (runFallbackRoutine == true), we run a search routine to find the correct input value of `insertAfter` and then rerun this function
            } else {
                insertAfter = getCorrectValueForInsertAfter(operator, updateBlock);
                _updateMiddlewareList(operator, updateBlock, insertAfter);
            }
        // In this case (insertAfter == HEAD), the `updateBlock` input should be before every other middleware's latest updateBlock.
        } else {
            /**
             * Check that `updateBlock` is before any other middleware's latest updateBlock.
             * If not, use the fallback routine to find the correct value for `insertAfter`.
             */
            if (_whitelistedContractDetails[operator][
                _uintToAddress(operatorToWhitelistedContractsByUpdate[operator].getHead()) ].latestUpdateBlock <= updateBlock)
            {
                runFallbackRoutine = true;
            }
            // if we have not marked `runFallbackRoutine` as 'true' yet, then that means the `insertAfter` input was correct on all counts
            if (!runFallbackRoutine) {
                /**
                 * Insert the middleware at the start (i.e. HEAD) of the list.
                 * This will fail if `msg.sender` is already in the list, which they shouldn't be because they were removed from the list above.
                 */
                require(operatorToWhitelistedContractsByUpdate[operator].pushFront(_addressToUint(msg.sender)), 
                    "Slasher.recordStakeUpdate: Preppending middleware unsuccessful");
            // in this case (runFallbackRoutine == true), we run a search routine to find the correct input value of `insertAfter` and then rerun this function
            } else {
                insertAfter = getCorrectValueForInsertAfter(operator, updateBlock);
                _updateMiddlewareList(operator, updateBlock, insertAfter);
            }
        }
    }

    function _addressToUint(address addr) internal pure returns(uint256) {
        return uint256(uint160(addr));
    }

    function _uintToAddress(uint256 x) internal pure returns(address) {
        return address(uint160(x));
    }    
}
