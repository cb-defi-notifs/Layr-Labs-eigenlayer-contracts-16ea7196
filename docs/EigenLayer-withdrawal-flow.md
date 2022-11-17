
# Withdrawal Flow

Withdrawals from EigenLayer are a multi-step process. This is necessary in order to ensure that funds can only be withdrawn once they are no longer placed 'at stake' on an active task of a service built on top of EigenLayer. For more details on the design of withdrawals and how they guarantee this, see the [Withdrawals Design Doc](./Guaranteed-stake-updates.md).

The first step of any withdrawal involves "queuing" the withdrawal itself. The staker who is withdrawing their assets can specify the InvestmentStrategy(s) they would like to withdraw from, as well as the respective amount of shares and token to withdraw from each of these strategies. Additionally, the staker can specify the address that will ultimately be able to withdraw the funds. Being able to specify an address different from their own allows stakers to "point their withdrawal" to a smart contract, which can potentially facilitate faster/instant withdrawals in the future.

## Queueing a Withdrawal
```solidity=
function queueWithdrawal(
        uint256[] calldata strategyIndexes,
        IInvestmentStrategy[] calldata strategies,
        IERC20[] calldata tokens,
        uint256[] calldata shares,
        WithdrawerAndNonce calldata withdrawerAndNonce,
        bool undelegateIfPossible)
```
* The staker starts a queued withdrawal by calling the `queueWithdrawal` function.  They set the receiver of the withdrawn funds as `withdrawer` address.  Calling `queueWithdrawal` also removes the user's shares in staker-specific storage and the shares delegated to the operator.  
* Shares in the strategies being withdrawn from, however, remain.  This ensures that the value per share reported by each strategy will remain consistent, and that the shares will continue to accrue gains (or losses!) from any strategy management until the withdrawal is completed.
* Finally, a hash of the withdrawal's details is stored to record that it has been created.

Note that there is a special case -- if the staker is withdrawing *all of their shares currently in EigenLayer, and they set the `undelegateIfPossible` to 'true'*, then with staker will be immediately 'undelegated' from the operator who they are currently delegated to. This allows them to change their delegation to a different operator if desired; in such a case, any *new* deposits by the staker will immediately be delegated to the new operator.


## Complete the Queued Withdrawal
```solidity=
function completeQueuedWithdrawal(
    QueuedWithdrawal calldata queuedWithdrawal,
    uint256 middlewareTimesIndex,
    bool receiveAsTokens)
```
* The withdrawer completes the queued withdrawal after the stake is inactive. They specify whether they would like the withdrawal in shares (to be redelegated in the future) or in tokens (to be removed from the EigenLayer platform).
* The withdrawer must specify an appropriate `middlewareTimesIndex` which proves that the withdrawn funds are no longer at stake on any active task. The appropriate index can be calculated off-chain and checked using the Slasher's `canWithdraw` function. For more details on this design, see the [Withdrawals Design Doc](./Guaranteed-stake-updates.md).

## Special Case -- Beacon Chain Withdrawals

Before *completing* a withdrawal of 'Beacon Chain ETH', the staker must trigger a withdrawal from the Beacon Chain (as of now this must be originated from the validating keys, but details could change as Ethereum finishes implementing Beacon Chain withdrawals). The staker's EigenPod's balance will eventually increase by the amount withdrawn. At that point, the validator will prove their withdrawal against the beacon chain state root via the `verifyBalanceUpdate` function.
Once the above is done, then when the withdrawal is completed through `InvestmentManager.completeQueuedWithdrawal`, the InvestmentManager will pass a call to `EigenPodManager.withdrawBeaconChainETH`, which will in turn pass a call onto the staker's EigenPod itself, invoking the `EigenPod.withdrawBeaconChainETH` function.



