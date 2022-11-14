# Guaranteed Stake Updates on Withdrawal
Withdrawals are one of the critical flows in the EigenLayer system.  Guaranteed stake updates ensures that all middlewares that an operator has opted into (i.e. delegated for slashing) are notified at the appropriate time regarding any withdrawals initiated by an operator.  To put it simply, an operator can "queue" a withdrawal at any point in time.  In order to complete the withdrawal, all of the operator's obligations related to keeping their stake slashable.  The contract `Slasher.sol` keeps track of the `latestServerUntil` time, which is the timestamp after which their stake has served its obligations.

## Storage Model

For each operator, we need to store:

1. A list of the contracts that are whitelisted to slash the operator
2. A `mapping(address => LinkedList<address>) operatorToWhitelistedContractsByUpdate`
, from operator address to a [linked list](https://github.com/vittominacori/solidity-linked-list/blob/master/contracts/StructuredLinkedList.sol) of addresses of all whitelisted contracts (these will always be in order of when their stakes were last updated earliest to latest)
3. A `mapping(address => mapping(address => uint32)) operatorToWhitelistedContractsToLatestUpdateTime` from operators to their whitelisted contracts to when they were updated
4. A `mapping(address => MiddlewareTimes[]) middlewareTimes` from operators to a list of
```solidity
struct MiddlewareTimes {
    uint32 updateTime; //the time at which this MiddlewareTimes update was appended
    uint32 earliestLastUpdateTime; //the time of update for the middleware whose latest update was earliest
    uint32 latestServeUntil; //the latest serve until time from all of the middleware that the operator is serving
}
```

Note:
`remove`, `nodeExists`,`getHead`, `getNextNode`, and `pushBack` are all constant time operations on linked lists. This is gained at the sacrifice of getting any elements at their *indexes* in the list. We should not need that typically integral functionality of lists as shown below.

## Helper Functions

### `_recordUpdateAndAddToMiddlewareTimes`

This function is called by a whitelisted slashing contract and records that the middleware has had a stake update and updates the storage as follows

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

        
        operatorToWhitelistedContractsByUpdate[operator].getHead() == msg.sender
        ?  operatorToWhitelistedContractsToLatestUpdateTime[
                operatorToWhitelistedContractsByUpdate[operator].getNextNode(msg.sender)
        ] 
        //otherwise keep it the same
        : curr.earliestLastUpdateTime
        // if the current middleware's serve until is later than the current recorded one, update the latestServeUntil
        latestServeUntil: serveUntil > curr.latestServeUntil ? serveUntil : curr.latestServeUntil
    })
}
```

## Public Functions

### `recordFirstStakeUpdate`

This function is called by a whitelisted slashing contract during registration stake updates passing in the time until which the operator's stake is bonded `serveUntil` and updates the storage as follows

```solidity
function recordFirstStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {
    //update latest update
    _recordUpdateAndAddToMiddlewareTimes(operator, serveUntil)
    //push the middleware to the end of the update list  
    require(operatorToWhitelistedContractsByUpdate[operator].pushBack(msg.sender))
}
```

### `recordStakeUpdate`

This function is called by a whitelisted slashing contract passing in the time until which the operator's stake is bonded `serveUntil` and records that the middleware has had a stake update and updates the storage as follows

```solidity
recordStakeUpdate(address operator, uint32 serveUntil) {
    //restrict to permissioned contracts
    require(canSlash(operator, msg.sender));
    //update latest update
    _recordUpdateAndAddToMiddlewareTimes(operator, serveUntil)
    //move the middleware to the end of the update list
    require(operatorToWhitelistedContractsByUpdate[operator].remove(msg.sender))
    require(operatorToWhitelistedContractsByUpdate[operator].pushBack(msg.sender))
}
```

### `recordLastStakeUpdate`

This function is called by a whitelisted slashing contract on deregistration passing in the time until which the operator's stake is bonded `serveUntil` and records that the middleware has had a stake update and updates the storage as follows

```solidity
recordLastStakeUpdate(address operator, uint32 serveUntil) {
    //restrict to permissioned contracts
    require(canSlash(operator, msg.sender));
    //update latest update
    _recordUpdateAndAddToMiddlewareTimes(operator, serveUntil)
    //remove the middleware from the list
    require(operatorToWhitelistedContractsByUpdate[operator].remove(msg.sender))
}
```

### `canWithdraw`

The biggest thing this upgrade does is it makes sure that withdrawals only happen once the stake being withdrawn is no longer slashable in a non optimistic way. This is done by calling the `canWithdraw` function on the slasher.

```solidity
canWithdaw(address operator, uint32 withdrawalStartTime, uint256 middlewareTimesIndex) (bool) {
    if (middlewareUpdates[operator].length == 0) {
        return true
    }
    //make the update time is after the withdrawalStartTime
    //make sure earliest update at the time is after withdrawalStartTime
    //make sure the current time is after the latestServeUntil at the time
    //this assures us that this update happened after the withdrawal and 
    //all middlewares were updated after the withdrawal and
    //the stake is no longer slashable
    MiddlewareUpdate update = middlewareUpdates[operator][middlewareTimesIndex];
    require(
            withdrawalStartTime < update.updateTime 
            &&
            withdrawalStartTime < update.earliestLastUpdateTime 
            &&
            uint32(block.timestamp) > update.latestServeUntil
    )   
}
```


## A More Intuitive Explanation

Let us say an operator has opted into a middleware, `Middleware A`.  He would call `recordFirstStakeUpdate`, adding  `Middleware A` to the linked list and recording the `updateBlock` and the `serveUntil` time in `operatorMiddlewareTimes`.  Then the operator registers with a second and third middleware, `Middleware B` and `Middleware C`.  At this point, the timeline is as follows:

![alt text](images/three_middlewares.png?raw=true "Title")

Based on this, the latest servUntil time is `serveUntil_B`.  So the most recent entry in the `operatorMiddlewareTimes` array for that operator will have `serveUntil = serveUntil_B` and `leastRecentUpdateBlock = updateBlock_A`.


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
The operator provides an entry from the `operatorMiddlewareTimes` based on which a withdrawal can be completed.   The withdrawability is checked by `slasher.canWithdraw()`, which checks that the block at which the withdrawal is queued, `withdrawalStartBlock` is less than the provided `operatorMiddlewareTimes` entry's leastRecentUpdateBlock.  It also checks that the current block.timestamp is greater than the `operatorMiddlewareTimes` entry's latestServeUntil.  If these criteria are met, the withdrawal can be completed.
















