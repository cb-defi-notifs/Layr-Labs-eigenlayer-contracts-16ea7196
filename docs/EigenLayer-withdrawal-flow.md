
# Withdrawal Flow

Currently, the withdrawal flow in the InvestmentManager contract is as follows:

## Queueing a Withdrawal
```solidity=
function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        WithdrawerAndNonce calldata withdrawerAndNonce
    )
        external
        whenNotPaused
        onlyNotFrozen(msg.sender)
        nonReentrant
        returns (bytes32)
```
* Depositer starts a queued withdrawal by calling the `queueWithdrawal` function.  They set the receiver of the withdrawn funds as `withdrawer` address.  Calling `queueWithdrawal` also removes the user's shares in staker-specific storage and the shares delegated to the operator.  
* Shares in the strategies being withdrawn from, however, remain.  This ensures that the value per share reported by each strategy will remain consistent, and that the shares will continue to accrue gains during the enforced WITHDRAWAL_WAITING_PERIOD.
* Finally, a "queued withdrawal" is initiated by storing a hash of the withdrawal's specifics.

## Starting the Withdrawal Waiting Period
```solidity=
function startQueuedWithdrawalWaitingPeriod(
    address depositor, 
    bytes32 withdrawalRoot, 
    uint32 stakeInactiveAfter
)
```
* Withdrawer then waits for the queued withdrawal transaction to be included in the chain, and then waits for *at least* `REASONABLE_STAKES_UPDATE_PERIOD`, after which they call `startQueuedWithdrawalWaitingPeriod` in order to initiate the withdrawal waiting period
* Either the end of the withdrawal waiting period or `stakeInactiveAfter` is set as timestamp for the unlocking of funds, whichever value is *later*
* The `unlockTimestamp` cannot be set before the `REASONABLE_STAKES_UPDATE_PERIOD` has passed, as there may be transactions that increase tasks on which the stake being withdrawn is considered active, meaning the proper value of `stakeInactiveAfter` cannot be known until after this period has elapsed
* 

## Complete the Queued Withdrawal
```solidity=
function completeQueuedWithdrawal(
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        address depositor,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bool receiveAsTokens
    )
        external
        whenNotPaused
        onlyNotFrozen(depositor)
        nonReentrant
```
* The withdrawer completes the queued withdrawal after the stake is inactive or a withdrawal fraud proof period has passed, whichever is longer. They specify whether they would like the withdrawal in shares (to be redelegated in the future) or in tokens (to be removed from the eigenlayer platform).



