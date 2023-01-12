# Solidity API

## InvestmentManager

This contract is for managing investments in different strategies. The main
functionalities are:
- adding and removing investment strategies that any delegator can invest into
- enabling deposit of assets into specified investment strategy(s)
- enabling removal of assets from specified investment strategy(s)
- recording deposit of ETH into settlement layer
- recording deposit of Eigen for securing EigenLayer
- slashing of assets for permissioned strategies

### GWEI_TO_WEI

```solidity
uint256 GWEI_TO_WEI
```

### PAUSED_DEPOSITS

```solidity
uint8 PAUSED_DEPOSITS
```

### PAUSED_WITHDRAWALS

```solidity
uint8 PAUSED_WITHDRAWALS
```

### WithdrawalQueued

```solidity
event WithdrawalQueued(address depositor, address withdrawer, address delegatedAddress, bytes32 withdrawalRoot)
```

Emitted when a new withdrawal is queued by `depositor`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address | Is the staker who is withdrawing funds from EigenLayer. |
| withdrawer | address | Is the party specified by `staker` who will be able to complete the queued withdrawal and receive the withdrawn funds. |
| delegatedAddress | address | Is the party who the `staker` was delegated to at the time of creating the queued withdrawal |
| withdrawalRoot | bytes32 | Is a hash of the input data for the withdrawal. |

### WithdrawalCompleted

```solidity
event WithdrawalCompleted(address depositor, address withdrawer, bytes32 withdrawalRoot)
```

Emitted when a queued withdrawal is completed

### onlyNotFrozen

```solidity
modifier onlyNotFrozen(address staker)
```

### onlyFrozen

```solidity
modifier onlyFrozen(address staker)
```

### onlyEigenPodManager

```solidity
modifier onlyEigenPodManager()
```

### onlyEigenPod

```solidity
modifier onlyEigenPod(address podOwner, address pod)
```

### constructor

```solidity
constructor(contract IEigenLayerDelegation _delegation, contract IEigenPodManager _eigenPodManager, contract ISlasher _slasher) public
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _delegation | contract IEigenLayerDelegation | The delegation contract of EigenLayer. |
| _eigenPodManager | contract IEigenPodManager | The contract that keeps track of EigenPod stakes for restaking beacon chain ether. |
| _slasher | contract ISlasher | The primary slashing contract of EigenLayer. |

### initialize

```solidity
function initialize(contract IPauserRegistry _pauserRegistry, address initialOwner) external
```

Initializes the investment manager contract. Sets the `pauserRegistry` (currently **not** modifiable after being set),
and transfers contract ownership to the specified `initialOwner`.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| _pauserRegistry | contract IPauserRegistry | Used for access control of pausing. |
| initialOwner | address | Ownership of this contract is transferred to this address. |

### depositBeaconChainETH

```solidity
function depositBeaconChainETH(address staker, uint256 amount) external
```

Deposits `amount` of beaconchain ETH into this contract on behalf of `staker`

_Only callable by EigenPodManager._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| staker | address | is the entity that is restaking in eigenlayer, |
| amount | uint256 | is the amount of beaconchain ETH being restaked, |

### recordOvercommittedBeaconChainETH

```solidity
function recordOvercommittedBeaconChainETH(address overcommittedPodOwner, uint256 beaconChainETHStrategyIndex, uint256 amount) external
```

Records an overcommitment event on behalf of a staker. The staker's beaconChainETH shares are decremented by `amount` and the 
EigenPodManager will subsequently impose a penalty upon the staker.

_Only callable by EigenPodManager._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| overcommittedPodOwner | address | is the pod owner to be slashed |
| beaconChainETHStrategyIndex | uint256 | is the index of the beaconChainETHStrategy in case it must be removed, |
| amount | uint256 | is the amount to decrement the slashedAddress's beaconChainETHStrategy shares |

### depositIntoStrategy

```solidity
function depositIntoStrategy(contract IInvestmentStrategy strategy, contract IERC20 token, uint256 amount) external returns (uint256 shares)
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

### depositIntoStrategyOnBehalfOf

```solidity
function depositIntoStrategyOnBehalfOf(contract IInvestmentStrategy strategy, contract IERC20 token, uint256 amount, address staker, uint256 expiry, bytes32 r, bytes32 vs) external returns (uint256 shares)
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
| r | bytes32 | and @param vs are the elements of the ECDSA signature |
| vs | bytes32 |  |

### undelegate

```solidity
function undelegate() external
```

Called by a staker to undelegate entirely from EigenLayer. The staker must first withdraw all of their existing deposits
(through use of the `queueWithdrawal` function), or else otherwise have never deposited in EigenLayer prior to delegating.

### queueWithdrawal

```solidity
function queueWithdrawal(uint256[] strategyIndexes, contract IInvestmentStrategy[] strategies, contract IERC20[] tokens, uint256[] shares, address withdrawer, bool undelegateIfPossible) external returns (bytes32)
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
| strategies | contract IInvestmentStrategy[] |  |
| tokens | contract IERC20[] |  |
| shares | uint256[] |  |
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

### _addShares

```solidity
function _addShares(address depositor, contract IInvestmentStrategy strategy, uint256 shares) internal
```

This function adds `shares` for a given `strategy` to the `depositor` and runs through the necessary update logic.

_In particular, this function calls `delegation.increaseDelegatedShares(depositor, strategy, shares)` to ensure that all
delegated shares are tracked, increases the stored share amount in `investorStratShares[depositor][strategy]`, and adds `strategy`
to the `depositor`'s list of strategies, if it is not in the list already._

### _depositIntoStrategy

```solidity
function _depositIntoStrategy(address depositor, contract IInvestmentStrategy strategy, contract IERC20 token, uint256 amount) internal returns (uint256 shares)
```

Internal function in which `amount` of ERC20 `token` is transferred from `msg.sender` to the InvestmentStrategy-type contract
`strategy`, with the resulting shares credited to `depositor`.

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| shares | uint256 | The amount of *new* shares in `strategy` that have been credited to the `depositor`. |

### _removeShares

```solidity
function _removeShares(address depositor, uint256 strategyIndex, contract IInvestmentStrategy strategy, uint256 shareAmount) internal returns (bool)
```

Decreases the shares that `depositor` holds in `strategy` by `shareAmount`.

_If the amount of shares represents all of the depositor`s shares in said strategy,
then the strategy is removed from investorStrats[depositor] and 'true' is returned. Otherwise 'false' is returned._

### _removeStrategyFromInvestorStrats

```solidity
function _removeStrategyFromInvestorStrats(address depositor, uint256 strategyIndex, contract IInvestmentStrategy strategy) internal
```

Removes `strategy` from `depositor`'s dynamic array of strategies, i.e. from `investorStrats[depositor]`

_the provided `strategyIndex` input is optimistically used to find the strategy quickly in the list. If the specified
index is incorrect, then we revert to a brute-force search._

### _undelegate

```solidity
function _undelegate(address depositor) internal
```

If the `depositor` has no existing shares, then they can `undelegate` themselves.
This allows people a "hard reset" in their relationship with EigenLayer after withdrawing all of their stake.

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

### calculateWithdrawalRoot

```solidity
function calculateWithdrawalRoot(struct IInvestmentManager.QueuedWithdrawal queuedWithdrawal) public pure returns (bytes32)
```

Returns the keccak256 hash of `queuedWithdrawal`.

