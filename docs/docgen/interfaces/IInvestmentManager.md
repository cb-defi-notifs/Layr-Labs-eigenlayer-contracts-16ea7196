# Solidity API

## IInvestmentManager

See the `InvestmentManager` contract itself for implementation details.

### StratsTokensShares

```solidity
struct StratsTokensShares {
  contract IInvestmentStrategy[] strategies;
  contract IERC20[] tokens;
  uint256[] shares;
}
```

### WithdrawerAndNonce

```solidity
struct WithdrawerAndNonce {
  address withdrawer;
  uint96 nonce;
}
```

### QueuedWithdrawal

```solidity
struct QueuedWithdrawal {
  contract IInvestmentStrategy[] strategies;
  contract IERC20[] tokens;
  uint256[] shares;
  address depositor;
  struct IInvestmentManager.WithdrawerAndNonce withdrawerAndNonce;
  uint32 withdrawalStartBlock;
  address delegatedAddress;
}
```

### depositIntoStrategy

```solidity
function depositIntoStrategy(contract IInvestmentStrategy strategy, contract IERC20 token, uint256 amount) external returns (uint256)
```

Deposits `amount` of `token` into the specified `strategy`, with the resultant shares credited to `depositor`

_The `msg.sender` must have previously approved this contract to transfer at least `amount` of `token` on their behalf.
Cannot be called by an address that is 'frozen' (this function will revert if the `msg.sender` is frozen)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategy | contract IInvestmentStrategy | is the specified strategy where investment is to be made, |
| token | contract IERC20 | is the denomination in which the investment is to be made, |
| amount | uint256 | is the amount of token to be invested in the strategy by the depositor |

### depositBeaconChainETH

```solidity
function depositBeaconChainETH(address staker, uint256 amount) external
```

Deposits `amount` of beaconchain ETH into this contract on behalf of `staker`

_Only callable by EigenPod for the staker._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| staker | address | is the entity that is restaking in eigenlayer, |
| amount | uint256 | is the amount of beaconchain ETH being restaked, |

### recordOvercommittedBeaconChainETH

```solidity
function recordOvercommittedBeaconChainETH(address overcommittedPodOwner, uint256 beaconChainETHStrategyIndex, uint256 amount) external
```

Records an overcommitment event on behalf of a staker. This allows EigenLayer to slash the overcommitted balance.
        It decreases the delegated shares, but does not freeze the `slashedAddress` completely.

_Only callable by EigenPod for the overcommittedPodOwner._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| overcommittedPodOwner | address | is the pod owner to be slashed |
| beaconChainETHStrategyIndex | uint256 | is the index of the beaconChainETHStrategy in case it must be removed, |
| amount | uint256 | is the amount of token overcommitted to EigenLayer |

### depositIntoStrategyOnBehalfOf

```solidity
function depositIntoStrategyOnBehalfOf(contract IInvestmentStrategy strategy, contract IERC20 token, uint256 amount, address staker, uint256 expiry, bytes signature) external returns (uint256 shares)
```

Used for investing an asset into the specified strategy with the resultant shared created to `staker`,
who must sign off on the action

_The `msg.sender` must have previously approved this contract to transfer at least `amount` of `token` on their behalf.
A signature is required for this function to eliminate the possibility of griefing attacks, specifically those
targetting stakers who may be attempting to undelegate.
Cannot be called on behalf of a staker that is 'frozen' (this function will revert if the `staker` is frozen)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategy | contract IInvestmentStrategy | is the specified strategy where investment is to be made, |
| token | contract IERC20 | is the denomination in which the investment is to be made, |
| amount | uint256 | is the amount of token to be invested in the strategy by the depositor |
| staker | address | the staker that the assets will be deposited on behalf of |
| expiry | uint256 | the timestamp at which the signature expires |
| signature | bytes | is a valid signature from the `staker`. either an ECDSA signature if the `staker` is an EOA, or data to forward following EIP-1271 if the `staker` is a contract |

### investorStratShares

```solidity
function investorStratShares(address user, contract IInvestmentStrategy strategy) external view returns (uint256 shares)
```

Returns the current shares of `user` in `strategy`

### getDeposits

```solidity
function getDeposits(address depositor) external view returns (contract IInvestmentStrategy[], uint256[])
```

Get all details on the depositor's investments and corresponding shares

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | contract IInvestmentStrategy[] | (depositor's strategies, shares in these strategies) |
| [1] | uint256[] |  |

### investorStratsLength

```solidity
function investorStratsLength(address staker) external view returns (uint256)
```

Simple getter function that returns `investorStrats[staker].length`.

### queueWithdrawal

```solidity
function queueWithdrawal(uint256[] strategyIndexes, struct IInvestmentManager.StratsTokensShares sts, address withdrawer, bool undelegateIfPossible) external returns (bytes32)
```

Called by a staker to queue a withdraw in the given token and shareAmount from each of the respective given strategies.

_Stakers will complete their withdrawal by calling the 'completeQueuedWithdrawal' function.
User shares are decreased in this function, but the total number of shares in each strategy remains the same.
The total number of shares is decremented in the 'completeQueuedWithdrawal' function instead, which is where
the funds are actually sent to the user through use of the strategies' 'withdrawal' function. This ensures
that the value per share reported by each strategy will remain consistent, and that the shares will continue
to accrue gains during the enforced WITHDRAWAL_WAITING_PERIOD.
Strategies are removed from `investorStrats` by swapping the last entry with the entry to be removed, then
popping off the last entry in `investorStrats`. The simplest way to calculate the correct `strategyIndexes` to input
is to order the strategies *for which `msg.sender` is withdrawing 100% of their shares* from highest index in
`investorStrats` to lowest index
Note that if the withdrawal includes shares in the enshrined 'beaconChainETH' strategy, then it must *only* include shares in this strategy, and
`withdrawer` must match the caller's address. The first condition is because slashing of queued withdrawals cannot be guaranteed 
for Beacon Chain ETH (since we cannot trigger a withdrawal from the beacon chain through a smart contract) and the second condition is because shares in
the enshrined 'beaconChainETH' strategy technically represent non-fungible positions (deposits to the Beacon Chain, each pointed at a specific EigenPod)._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| strategyIndexes | uint256[] | is a list of the indices in `investorStrats[msg.sender]` that correspond to the strategies for which `msg.sender` is withdrawing 100% of their shares |
| sts | struct IInvestmentManager.StratsTokensShares |  |
| withdrawer | address |  |
| undelegateIfPossible | bool |  |

### completeQueuedWithdrawal

```solidity
function completeQueuedWithdrawal(struct IInvestmentManager.QueuedWithdrawal queuedWithdrawal, uint256 middlewareTimesIndex, bool receiveAsTokens) external
```

Used to complete the specified `queuedWithdrawal`. The function caller must match `queuedWithdrawal.withdrawer`

_middlewareTimesIndex should be calculated off chain before calling this function by finding the first index that satisfies `slasher.canWithdraw`_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| queuedWithdrawal | struct IInvestmentManager.QueuedWithdrawal | The QueuedWithdrawal to complete. |
| middlewareTimesIndex | uint256 | is the index in the operator that the staker who triggered the withdrawal was delegated to's middleware times array |
| receiveAsTokens | bool | If true, the shares specified in the queued withdrawal will be withdrawn from the specified strategies themselves and sent to the caller, through calls to `queuedWithdrawal.strategies[i].withdraw`. If false, then the shares in the specified strategies will simply be transferred to the caller directly. |

### slashShares

```solidity
function slashShares(address slashedAddress, address recipient, contract IInvestmentStrategy[] strategies, contract IERC20[] tokens, uint256[] strategyIndexes, uint256[] shareAmounts) external
```

Slashes the shares of a 'frozen' operator (or a staker delegated to one)

_strategies are removed from `investorStrats` by swapping the last entry with the entry to be removed, then
popping off the last entry in `investorStrats`. The simplest way to calculate the correct `strategyIndexes` to input
is to order the strategies *for which `msg.sender` is withdrawing 100% of their shares* from highest index in
`investorStrats` to lowest index_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| slashedAddress | address | is the frozen address that is having its shares slashed |
| recipient | address | The slashed funds are withdrawn as tokens to this address. |
| strategies | contract IInvestmentStrategy[] |  |
| tokens | contract IERC20[] |  |
| strategyIndexes | uint256[] | is a list of the indices in `investorStrats[msg.sender]` that correspond to the strategies for which `msg.sender` is withdrawing 100% of their shares |
| shareAmounts | uint256[] |  |

### slashQueuedWithdrawal

```solidity
function slashQueuedWithdrawal(address recipient, struct IInvestmentManager.QueuedWithdrawal queuedWithdrawal) external
```

Slashes an existing queued withdrawal that was created by a 'frozen' operator (or a staker delegated to one)

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| recipient | address | The funds in the slashed withdrawal are withdrawn as tokens to this address. |
| queuedWithdrawal | struct IInvestmentManager.QueuedWithdrawal |  |

### calculateWithdrawalRoot

```solidity
function calculateWithdrawalRoot(struct IInvestmentManager.QueuedWithdrawal queuedWithdrawal) external pure returns (bytes32)
```

Returns the keccak256 hash of `queuedWithdrawal`.

### delegation

```solidity
function delegation() external view returns (contract IEigenLayerDelegation)
```

Returns the single, central Delegation contract of EigenLayer

### slasher

```solidity
function slasher() external view returns (contract ISlasher)
```

Returns the single, central Slasher contract of EigenLayer

### beaconChainETHStrategy

```solidity
function beaconChainETHStrategy() external view returns (contract IInvestmentStrategy)
```

returns the enshrined beaconChainETH Strategy

