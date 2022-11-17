
# Withdrawal Flow

Withdrawals from EigenLayer are a multi-step process. This is necessary in order to ensure that funds can only be withdrawn once they are no longer placed 'at stake' on an active task of a service built on top of EigenLayer. For more details on the design of withdrawals and how they guarantee this, see the [Withdrawals Design Doc](./Guaranteed-stake-updates.md).

The first step of any withdrawal involves "queuing" the withdrawal itself. The staker who is withdrawing their assets can specify the InvestmentStrategy(s) they would like to withdraw from, as well as the respective amount of shares and token to withdraw from each of these strategies. Additionally, the staker can specify the address that will ultimately be able to withdraw the funds. Being able to specify an address different from their own allows stakers to "point their withdrawal" to a smart contract, which can potentially facilitate faster/instant withdrawals in the future.

## Queueing a Withdrawal

![Queuing a Withdrawal](images/EL_queuing_a_withdrawal.png?raw=true "Queuing a Withdrawal")

1. The staker starts a queued withdrawal by calling the `InvestmentManager.queueWithdrawal` function.  They set the receiver of the withdrawn funds as `withdrawer` address. Calling `queueWithdrawal` also removes the user's shares in staker-specific storage and the shares delegated to the operator. Shares in the strategies being withdrawn from, however, remain.  This ensures that the value per share reported by each strategy will remain consistent, and that the shares will continue to accrue gains (or losses!) from any strategy management until the withdrawal is completed.
2. Prior to actually performing the above processing, the InvestmentManager calls `Slasher.isFrozen` to ensure that the staker is not 'frozen' in EigenLayer (due to them or the operator they delegate to being slashed).
3. The InvestmentManager calls `EigenLayerDelegation.decreaseDelegatedShares` to account for any necessary decrease in delegated shares (the EigenLayerDelegation contract will not modify its storage if the staker is not an operator and not actively delegated to one).
4. The InvestmentManager queries `EigenLayerDelegation.delegatedTo` to get the account that the caller is *currently delegated to*. A hash of the withdrawal's details – including the account that the caller is currently delegated to – is stored in the InvestmentManager, to record that the queued withdrawal has been created and store details which can be checked against when the withdrawal is completed.
5. If the the staker is withdrawing *all of their shares currently in EigenLayer, and they set the `undelegateIfPossible` input to 'true'*, then with staker will be immediately 'undelegated' from the operator who they are currently delegated to, through the InvestmentManager making a call to `EigenLayerDelegation.undelegate`. This allows the staker to immediately change their delegation to a different operator if desired; in such a case, any *new* deposits by the staker will immediately be delegated to the new operator, while the withdrawn funds will be 'in limbo' until the withdrawal is completed.

## Completing a Queued Withdrawal

![Completing a Queued Withdrawal](images/EL_completing_queued_withdrawal.png?raw=true "Completing a Queued Withdrawal")

1. The withdrawer completes the queued withdrawal after the stake is inactive, by calling `InvestmentManager.completeQueuedWithdrawal`. They specify whether they would like the withdrawal in shares (to be redelegated in the future) or in tokens (to be removed from the EigenLayer platform), through the `withdrawAsTokens` input flag. The withdrawer must also specify an appropriate `middlewareTimesIndex` which proves that the withdrawn funds are no longer at stake on any active task. The appropriate index can be calculated off-chain and checked using the `Slasher.canWithdraw` function. For more details on this design, see the [Withdrawals Design Doc](./Guaranteed-stake-updates.md).
2. The InvestmentManager calls `Slasher.isFrozen` to ensure that the staker who initiated the withdrawal is not 'frozen' in EigenLayer (due to them or the operator they delegate to being slashed). In the event that they are frozen, this indicates that the to-be-withdrawn funds are likely subject to slashing.
3. Depending on the value of the supplied `withdrawAsTokens` input flag:
* If `withdrawAsTokens` is set to 'true', then InvestmentManager calls `InvestmentStrategy.withdraw` on each of the strategies being withdrawn from, causing the withdrawn funds to be transferred from each of the strategies to the withdrawer.
OR
* If `withdrawAsTokens` is set to 'false', then InvestmentManager increases the stored share amounts that the withdrawer has in the strategies in question (effectively completing the transfer of shares from the initiator of the withdrawal to the withdrawer), and then calls `EigenLayerDelegation.increaseDelegatedShares` to trigger any appropriate updates to delegated share amounts.

## Special Case -- Beacon Chain Withdrawals

If a withdrawal includes withdrawing  'Beacon Chain ETH' from Eigenlayer, then before *completing* the withdrawal, the staker must trigger a withdrawal from the Beacon Chain (as of now this must be originated from the validating keys, but details could change as Ethereum finishes implementing Beacon Chain withdrawals). The staker's EigenPod's balance will eventually increase by the amount withdrawn, and this change will be reflected in a BeaconChainOracle state root update. At that point, the validator will prove their withdrawal against the beacon chain state root via the `verifyBalanceUpdate` function.
Once the above is done, then when the withdrawal is completed through `InvestmentManager.completeQueuedWithdrawal` (as above), the InvestmentManager will pass a call to `EigenPodManager.withdrawBeaconChainETH`, which will in turn pass a call onto the staker's EigenPod itself, invoking the `EigenPod.withdrawBeaconChainETH` function and triggering the actual transfer of ETH from the EigenPod to the withdrawer.



