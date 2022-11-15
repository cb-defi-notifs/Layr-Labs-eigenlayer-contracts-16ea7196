# Guaranteed Stake Updates on Withdrawal
Withdrawals are one of the critical flows in the EigenLayer system.  Guaranteed stake updates ensure that all middlewares that an operator has opted into (i.e. allowed to slash them) are notified at the appropriate time regarding any withdrawals initiated by an operator.  To put it simply, an operator can "queue" a withdrawal at any point in time.  In order to complete the withdrawal, the operator must first serve all existing obligations related to keeping their stake slashable.  The contract `Slasher.sol` keeps track of a historic record of each operator's  `latestServeUntil` time, which is the timestamp after which their stake will have served its obligations. To complete a withdrawal, an operator (or a staker delegated to them) can point to a relevant point in the record which proves that the funds they are withdrawing are no longer "at stake" on any middleware tasks.

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
```solidity
    function _recordUpdateAndAddToMiddlewareTimes(address operator, uint32 updateBlock, uint32 serveUntil) internal {
```

This function is called each time a middleware posts a stake update, through a call to `recordFirstStakeUpdate`, `recordStakeUpdate`, or `recordLastStakeUpdate`. It records that the middleware has had a stake update and pushes a new entry to the operator's list of 'MiddlewareTimes', i.e. `middlewareTimes[operator]`, if *either* the `operator`'s 
leastRecentUpdateBlock' has increased, *or* their latestServeUntil' has increased.

## Public Functions

### `recordFirstStakeUpdate`
```solidity
    function recordFirstStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {

```

This function is called by a whitelisted slashing contract during registration of a new operator. The middleware posts an initial update, passing in the time until which the `operator`'s stake is bonded -- `serveUntil`. The middleware is pushed to the end ('TAIL') of the linked list since in `operatorToWhitelistedContractsByUpdate[operator]`, since the new middleware most have been updated the most recently, i.e. at the present moment.


### `recordStakeUpdate`
```solidity
recordStakeUpdate(address operator, uint32 updateBlock, uint32 serveUntil, uint256 insertAfter) 

```

This function is called by a whitelisted slashing contract, passing in the time until which the operator's stake is bonded -- `serveUntil`, the block for which the stake update to the middleware is being recorded (which may be the current block or a past block) -- `updateBlock`, and an index specifying the element of the `operator`'s linked list that the currently updating middleware should be inserted after -- `insertAfter`.

### `recordLastStakeUpdate`
```solidity
function recordLastStakeUpdate(address operator, uint32 serveUntil) external onlyCanSlash(operator) {
```

This function is called by a whitelisted slashing contract on deregistration of an operator, passing in the time until which the operator's stake is bonded -- `serveUntil`. It assumes that the update is posted for the *current* block, rather than a past block, in contrast to `recordStakeUpdate`.


### `canWithdraw`
```solidity
canWithdraw(address operator, uint32 withdrawalStartBlock, uint256 middlewareTimesIndex) external returns (bool) {
```

The biggest thing guaranteed stake updates do is to make sure that withdrawals only happen once the stake being withdrawn is no longer slashable in a non-optimistic way. This is done by calling the `canWithdraw` function on the Slasher contract, which returns 'true' if the `operator` can currently complete a withdrawal started at the `withdrawalStartBlock`, with `middlewareTimesIndex` used to specify the index of a `MiddlewareTimes` struct in the operator's list (i.e. an index in `operatorToMiddlewareTimes[operator]`). The specified struct is consulted as proof of the `operator`'s ability (or lack thereof) to complete the withdrawal.


## An Instructive Example

Let us say an operator has opted into serving a middleware, `Middleware A`. As a result of the operator's actions, `MiddlewareA` calls `recordFirstStakeUpdate`, adding  `Middleware A` to the linked list and recording the `block.number` as the `updateBlock` and the middleware's specified `serveUntil` time in `operatorMiddlewareTimes`.  At later times, the operator registers with a second and third middleware, `Middleware B` and `Middleware C`, respectively.  At this point, the timeline is as follows:

![Three Middlewares](images/three_middlewares.png?raw=true "Title")

Based on this, the latest serveUntil time is `serveUntil_B`, and the 'stalest' stake update from a middleware occurred at `updateBlock_A`.  So the most recent entry in the `operatorMiddlewareTimes` array for the operator will have `serveUntil = serveUntil_B` and `leastRecentUpdateBlock = updateBlock_A`.


In the meantime, let us say that the operator had also queued a withdrawal between opting-in to serve `Middleware A` and opting-in to serve `Middleware B`:

![Three Middlewares With Queued Withdrawal](images/three_middlewares_withdrwawl_queued.png?raw=true "Title")

Now that a withdrawal has been queued, the operator must wait till their obligations have been met before they can withdraw their stake.  At this point, in our example, the `operatorMiddlewareTimes` array looks like this:

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
The reason we store an array of updates as opposed to one `MiddlewareTimes` struct with the most up-to-date values is that this would require pushing updates carefully to not disrupt existing withdrawals. This way, operators can select the `MiddlewareTimes` entry that is appropriate for their withdrawal.  Thus, the operator provides an entry from the `operatorMiddlewareTimes` based on which a withdrawal can be completed.   The withdrawability is checked by `slasher.canWithdraw()`, which checks that for the block at which the withdrawal is queued, `withdrawalStartBlock` is less than the provided `operatorMiddlewareTimes` entry's 'leastRecentUpdateBlock'.  It also checks that the current block.timestamp is greater than the `operatorMiddlewareTimes` entry's 'latestServeUntil'.  If these criteria are met, the withdrawal can be completed.  In order to complete a withdrawal in this example, the operator would have to record a stake update in `Middleware A`, signalling readiness for withdrawal.  The timeline would now look like this:

![Updated Three Middlewares With Queued Withdrawal](images/withdrawal.png?raw=true "Title")






















