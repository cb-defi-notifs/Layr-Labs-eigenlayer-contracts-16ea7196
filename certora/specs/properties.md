Author: Yura Sherman



## Withdrawal

- Cannot withdraw full funds if slashed
- Cannot withdraw funds without appropriate delay
- Cannot withdraw funds which are at risk of slashing
- Cannot withdraw funds if middlewares haven't been updated (recording the incoming decrease in funds)
- A queued withdrawal can be completed if it's pending and no longer slashable
- A queued withdrawal can still be slashed

## Slashing

- slashing happens if and only if a provably malicious action by an operator took place
- operator may be slashed only if allowToSlash() for that particular contract was called
- slashing cannot happen after bondedUntil[operator][contractAddress] timestamp
- bondedUntil[operator][contractAddress] changed  => allowToSlash() or recordLastStakeUpdateAndRevokeSlashingAbility() was called
- recordLastStakeUpdateAndRevokeSlashingAbility() should only be callable when bondedUntil[operator][contractAddress] == MAX_BONDED_UNTIL, and only by the contractAddress
- Any contractAddress for which bondedUntil[operator][contractAddress] > current time can call freezeOperator(operator).
- frozen operator cannot make deposits/withdrawals, cannot complete queued withdrawals
- slashing and unfreezing is performed by the InvestmentManager contract owner (is it permanent or configurable?)
- frozenStatus[operator] changed => freezeOperator() or resetFrozenStatus() were called


## InvestmentManager

- totalShares per strategy == Σ investorStratShares[staker][strategy] for all stakers
- investorStratShares[staker][strategy] increase => depositIntoStrategy() or depositIntoStrategyOnBehalfOf() have been invoked
- investorStratShares[staker][strategy] decrease => queueWithdrawal() or slashShares() have been invoked
- investorStrats[staker] should contain all strategies for which investorStratShares[staker][strategy] is nonzero
- investorStrats[staker] should contain no strategies for which investorStratShares[staker][strategy] is zero

## Investment Strategy

- balance of underlyingToken >= total supply of shares ( depends on how slashing works ?)

## Delegation

- a staker must be either registered as an operator or delegate to an operator
- after registerAsOperator() is called, delegationTerms[operator] != 0
- for an operator, delegatedTo[operator] == operator (operators are delegated to themselves)
- operatorShares[operator][strategy] should increase only when delegateTo() delegateToBySignature(), or increaseDelegatedShares() is called
- operatorShares[operator][strategy] should decrease only when either of the two decreaseDelegatedShares() is called
- sum of operatorShares[operator][strategy] for all operators <= sum of InvestmentManager.investorStratShares[staker][strategy]

- undelegate is only possible by queueing withdrawals for all of their deposited assets.
