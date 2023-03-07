# Solidity API

## IDelayedWithdrawalRouter

### Payment

```solidity
struct Payment {
  uint224 amount;
  uint32 blockCreated;
}
```

### UserPayments

```solidity
struct UserPayments {
  uint256 paymentsCompleted;
  struct IDelayedWithdrawalRouter.Payment[] payments;
}
```

### createPayment

```solidity
function createPayment(address podOwner, address recipient) external payable
```

Creates an delayed withdrawal for `msg.value` to the `recipient`.

_Only callable by the `podOwner`'s EigenPod contract._

### claimPayments

```solidity
function claimPayments(address recipient, uint256 maxNumberOfWithdrawalsToClaim) external
```

Called in order to withdraw delayed withdrawals made to the `recipient` that have passed the `withdrawalDelayBlocks` period.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| recipient | address | The address to claim payments for. |
| maxNumberOfWithdrawalsToClaim | uint256 | Used to limit the maximum number of withdrawals to loop through claiming. |

### claimPayments

```solidity
function claimPayments(uint256 maxNumberOfWithdrawalsToClaim) external
```

Called in order to withdraw delayed withdrawals made to the caller that have passed the `withdrawalDelayBlocks` period.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| maxNumberOfWithdrawalsToClaim | uint256 | Used to limit the maximum number of withdrawals to loop through claiming. |

### setWithdrawalDelayBlocks

```solidity
function setWithdrawalDelayBlocks(uint256 newValue) external
```

Owner-only function for modifying the value of the `withdrawalDelayBlocks` variable.

### userWithdrawals

```solidity
function userWithdrawals(address user) external view returns (struct IDelayedWithdrawalRouter.UserPayments)
```

Getter function for the mapping `_userWithdrawals`

### userPaymentByIndex

```solidity
function userPaymentByIndex(address user, uint256 index) external view returns (struct IDelayedWithdrawalRouter.Payment)
```

Getter function for fetching the payment at the `index`th entry from the `_userWithdrawals[user].payments` array

### userWithdrawalsLength

```solidity
function userWithdrawalsLength(address user) external view returns (uint256)
```

Getter function for fetching the length of the payments array of a specific user

### canClaimPayment

```solidity
function canClaimPayment(address user, uint256 index) external view returns (bool)
```

Convenience function for checking whethere or not the payment at the `index`th entry from the `_userWithdrawals[user].payments` array is currently claimable

### withdrawalDelayBlocks

```solidity
function withdrawalDelayBlocks() external view returns (uint256)
```

Delay enforced by this contract for completing any payment. Measured in blocks, and adjustable by this contract's owner,
up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).

