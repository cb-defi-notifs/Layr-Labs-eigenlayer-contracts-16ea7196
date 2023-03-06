# Solidity API

## EigenPodPaymentEscrow

### WithdrawalDelayBlocksSet

```solidity
event WithdrawalDelayBlocksSet(uint256 previousValue, uint256 newValue)
```

Emitted when the `withdrawalDelayBlocks` variable is modified from `previousValue` to `newValue`.

### PAUSED_PAYMENT_CLAIMS

```solidity
uint8 PAUSED_PAYMENT_CLAIMS
```

### withdrawalDelayBlocks

```solidity
uint256 withdrawalDelayBlocks
```

Delay enforced by this contract for completing any payment. Measured in blocks, and adjustable by this contract's owner,
up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).

### MAX_WITHDRAWAL_DELAY_BLOCKS

```solidity
uint256 MAX_WITHDRAWAL_DELAY_BLOCKS
```

### eigenPodManager

```solidity
contract IEigenPodManager eigenPodManager
```

The EigenPodManager contract of EigenLayer.

### _userPayments

```solidity
mapping(address => struct IEigenPodPaymentEscrow.UserPayments) _userPayments
```

Mapping: user => struct storing all payment info. Marked as internal with an external getter function named `userPayments`

### PaymentCreated

```solidity
event PaymentCreated(address podOwner, address recipient, uint256 amount, uint256 index)
```

event for payment creation

### PaymentsClaimed

```solidity
event PaymentsClaimed(address recipient, uint256 amountClaimed, uint256 paymentsCompleted)
```

event for the claiming of payments

### onlyEigenPod

```solidity
modifier onlyEigenPod(address podOwner)
```

Modifier used to permission a function to only be called by the EigenPod of the specified `podOwner`

### constructor

```solidity
constructor(contract IEigenPodManager _eigenPodManager) public
```

### initialize

```solidity
function initialize(address initOwner, contract IPauserRegistry _pauserRegistry, uint256 initPausedStatus, uint256 _withdrawalDelayBlocks) external
```

### createPayment

```solidity
function createPayment(address podOwner, address recipient) external payable
```

Creates an escrowed payment for `msg.value` to the `recipient`.

_Only callable by the `podOwner`'s EigenPod contract._

### claimPayments

```solidity
function claimPayments(address recipient, uint256 maxNumberOfPaymentsToClaim) external
```

Called in order to withdraw escrowed payments made to the `recipient` that have passed the `withdrawalDelayBlocks` period.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| recipient | address | The address to claim payments for. |
| maxNumberOfPaymentsToClaim | uint256 | Used to limit the maximum number of payments to loop through claiming. |

### claimPayments

```solidity
function claimPayments(uint256 maxNumberOfPaymentsToClaim) external
```

Called in order to withdraw escrowed payments made to the caller that have passed the `withdrawalDelayBlocks` period.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| maxNumberOfPaymentsToClaim | uint256 | Used to limit the maximum number of payments to loop through claiming. |

### setWithdrawalDelayBlocks

```solidity
function setWithdrawalDelayBlocks(uint256 newValue) external
```

Owner-only function for modifying the value of the `withdrawalDelayBlocks` variable.

### userPayments

```solidity
function userPayments(address user) external view returns (struct IEigenPodPaymentEscrow.UserPayments)
```

Getter function for the mapping `_userPayments`

### claimableUserPayments

```solidity
function claimableUserPayments(address user) external view returns (struct IEigenPodPaymentEscrow.Payment[])
```

Getter function to get all payments that are currently claimable by the `user`

### userPaymentByIndex

```solidity
function userPaymentByIndex(address user, uint256 index) external view returns (struct IEigenPodPaymentEscrow.Payment)
```

Getter function for fetching the payment at the `index`th entry from the `_userPayments[user].payments` array

### userPaymentsLength

```solidity
function userPaymentsLength(address user) external view returns (uint256)
```

Getter function for fetching the length of the payments array of a specific user

### canClaimPayment

```solidity
function canClaimPayment(address user, uint256 index) external view returns (bool)
```

Convenience function for checking whethere or not the payment at the `index`th entry from the `_userPayments[user].payments` array is currently claimable

### _claimPayments

```solidity
function _claimPayments(address recipient, uint256 maxNumberOfPaymentsToClaim) internal
```

internal function used in both of the overloaded `claimPayments` functions

### _setWithdrawalDelayBlocks

```solidity
function _setWithdrawalDelayBlocks(uint256 newValue) internal
```

internal function for changing the value of `withdrawalDelayBlocks`. Also performs sanity check and emits an event.

### __gap

```solidity
uint256[48] __gap
```

_This empty reserved space is put in place to allow future versions to add new
variables without shifting down storage in the inheritance chain.
See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps_

