# Guaranteed Stake Updates on Withdrawal
Withdrawals are one of the critical flows in the EigenLayer system.  Guaranteed stake updates ensure that all middlewares that an operator has opted into (i.e. allowed to slash them) are notified at the appropriate time regarding any withdrawals initiated by an operator.  To put it simply, an operator can "queue" a withdrawal at any point in time.  In order to complete the withdrawal, all of the operator must first serve all obligations related to keeping their stake slashable.  The contract `Slasher.sol` keeps track of the `latestServeUntil` time, which is the timestamp after which their stake will have served its obligations.

## Storage Model

For each operator, we need to store:

1. A list of the contracts that are whitelisted to slash the operator
2. A `mapping(address => LinkedList<address>) operatorToWhitelistedContractsByUpdate`, from operator address to a [linked list](../src/contracts/libraries/StructuredLinkedList.sol) of addresses of all whitelisted contract, ordered by when their stakes were last updated, from earliest (at the 'HEAD' of the list) to latest (at the 'TAIL' of the list)
3. A `mapping(address => mapping(address => uint32)) operatorToWhitelistedContractsToLatestUpdateTime` from operators to their whitelisted contracts to when they were updated
4. A `mapping(address => MiddlewareTimes[]) middlewareTimes` from operators to a list of
```solidity
struct MiddlewareTimes {
        // The update block for the middleware whose most recent update was earliest, i.e. the 'stalest' update
        uint32 leastRecentUpdateBlock;
        // The latest 'serve until' time from all of the middleware that the operator is serving
        uint32 latestServeUntil;
    }
```

Note:
`remove`, `nodeExists`,`getHead`, `getNextNode`, and `pushBack` are all constant time operations on linked lists. This is gained at the sacrifice of getting any elements at their *indexes* in the list. We should not need that typically integral functionality of lists as shown below.

## Helper Functions

### `_recordUpdateAndAddToMiddlewareTimes`

This function is called by a whitelisted slashing contract. It records that the middleware has had a stake update and updates the storage as follows:

```solidity
_recordUpdateAndAddToMiddlewareTimes(address operator, uint32 serveUntil) {
    //update latest update block
    operatorToWhitelistedContractsToLatestUpdateBlock[operator][msg.sender] = updateBlock;

    //load current middleware times tip
    MiddlewareTimes curr = peratorToMiddlewareTimes[operator][operatorToMiddlewareTimes[operator].length - 1];

    //create next entry in middleware times
    MiddlewareTimes next = MiddlewareTimes({
        //if new serveUntil is later than curr.latestServeUntil, we reset the latestServeUntil
        latestServeUntil = serveUntil or curr.latestServeUntil
            
        //
        leastRecentUpdateBlock = curr.leastRecentUpdateBlock
        if middleware is the head of the linked list aka first middleware in the list, we update it. Then we query the next middleware in the list for the new updateBlock
        if(nextMiddlewaresLeastRecentUpdateBlock < updateBlock):
            leastRecentUpdateBlock = nextMiddlewaresLeastRecentUpdateBlock
        else{
            leastRecentUpdateBlock = updateBlock;
        }
    }

}
```

## Public Functions

### `recordFirstStakeUpdate`

This function is called by a whitelisted slashing contract during registration stake updates passing in the time until which the operator's stake is bonded `serveUntil` and updates the storage as follows

```solidity
recordFirstStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {

        // update latest update

        _recordUpdateAndAddToMiddlewareTimes(operator, uint32(block.number), serveUntil);


        // Push the middleware to the end of the update list. This will fail if the caller *is* already in the list.
        require(operatorToWhitelistedContractsByUpdate[operator].pushBack(addressToUint(msg.sender)), 
            "Slasher.recordFirstStakeUpdate: Appending middleware unsuccessful");
    }
```

### `recordStakeUpdate`

This function is called by a whitelisted slashing contract passing in the time until which the operator's stake is bonded `serveUntil` and records that the middleware has had a stake update and updates the storage as follows

```solidity
recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 insertAfter) 
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
```

### `recordLastStakeUpdate`

This function is called by a whitelisted slashing contract on deregistration passing in the time until which the operator's stake is bonded `serveUntil` and records that the middleware has had a stake update and updates the storage as follows

```solidity
function recordLastStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {
        // update the 'stalest' stakes update time + latest 'serveUntil' time of the `operator`
        _recordUpdateAndAddToMiddlewareTimes(operator, uint32(block.number), serveUntil);
        //remove the middleware from the list
        require(operatorToWhitelistedContractsByUpdate[operator].remove(addressToUint(msg.sender)) != 0,
             "Slasher.recordLastStakeUpdate: Removing middleware unsuccessful");
    }
```

### `canWithdraw`

The biggest thing this upgrade does is it makes sure that withdrawals only happen once the stake being withdrawn is no longer slashable in a non optimistic way. This is done by calling the `canWithdraw` function on the slasher.

```solidity
canWithdraw(address operator, uint32 withdrawalStartBlock, uint256 middlewareTimesIndex) external returns (bool) {
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
            withdrawalStartBlock < update.leastRecentUpdateBlock 
            &&
            uint32(block.timestamp) > update.latestServeUntil
        );
    }
```


## A More Intuitive Explanation

Let us say an operator has opted into a middleware, `Middleware A`.  The operator would call `recordFirstStakeUpdate`, adding  `Middleware A` to the linked list and recording the `updateBlock` and the `serveUntil` time in `operatorMiddlewareTimes`.  Then the operator registers with a second and third middleware, `Middleware B` and `Middleware C`.  At this point, the timeline is as follows:

![alt text](images/three_middlewares.png?raw=true "Title")

Based on this, the latest serveUntil time is `serveUntil_B`.  So the most recent entry in the `operatorMiddlewareTimes` array for that operator will have `serveUntil = serveUntil_B` and `leastRecentUpdateBlock = updateBlock_A`.


In the mean time, let us say the operator had also queued a withdrawal between the leastRecentUpdateBlock of `Middleware A` and `Middleware B`:

![alt text](images/three_middlewares_withdrwawl_queued.png?raw=true "Title")

Now that a withdrawal has been queued, the operator must wait till their obligations have been met before they can withdraw their stake. .  At this point, in our example, the `operatorMiddlewareTimes` array looks like this:

```solidity
{
    {
        leastRecentUpdateBlock: updateBlock_A
        latestServeUntil: serveUntil_A
    },
    {
        leastRecentUpdateBlock: updateBlock_A
        latestServeUntil: serveUntil_B
    },
    {
        leastRecentUpdateBlock: updateBlock_A
        latestServeUntil: serveUntil_B
    }
}
```
The reason we store an array of updates as opposed to one `MiddlewareTimes` struct with the most up to date values is that this would require pushing updates carefully to not disrupt existing withdrawals. This way, operators can select the `MiddlewareTimes` entry that is appropriate for their withdrawal.  Thus, the operator provides an entry from the `operatorMiddlewareTimes` based on which a withdrawal can be completed.   The withdrawability is checked by `slasher.canWithdraw()`, which checks that the block at which the withdrawal is queued, `withdrawalStartBlock` is less than the provided `operatorMiddlewareTimes` entry's leastRecentUpdateBlock.  It also checks that the current block.timestamp is greater than the `operatorMiddlewareTimes` entry's latestServeUntil.  If these criteria are met, the withdrawal can be completed.  In order to complete a withdrawal in this example, the operator would have to record a stake update in `Middleware A`, signalling readiness for withdrawal.  The timeline would now look like this:

![alt text](images/withdrawal.png?raw=true "Title")






















