# Solidity API

## IEigenPod

### VALIDATOR_STATUS

```solidity
enum VALIDATOR_STATUS {
  INACTIVE,
  ACTIVE,
  OVERCOMMITTED,
  WITHDRAWN
}
```

### PartialWithdrawalClaim

```solidity
struct PartialWithdrawalClaim {
  enum IEigenPod.PARTIAL_WITHDRAWAL_CLAIM_STATUS status;
  uint32 creationBlockNumber;
  uint32 fraudproofPeriodEndBlockNumber;
  uint64 partialWithdrawalAmountGwei;
}
```

### PARTIAL_WITHDRAWAL_CLAIM_STATUS

```solidity
enum PARTIAL_WITHDRAWAL_CLAIM_STATUS {
  REDEEMED,
  PENDING,
  FAILED
}
```

### PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS

```solidity
function PARTIAL_WITHDRAWAL_FRAUD_PROOF_PERIOD_BLOCKS() external view returns (uint32)
```

The length, in blocks, if the fraud proof period following a claim on the amount of partial withdrawals in an EigenPod

### REQUIRED_BALANCE_GWEI

```solidity
function REQUIRED_BALANCE_GWEI() external view returns (uint64)
```

The amount of eth, in gwei, that is restaked per validator

### OVERCOMMITMENT_PENALTY_AMOUNT_GWEI

```solidity
function OVERCOMMITMENT_PENALTY_AMOUNT_GWEI() external view returns (uint64)
```

The amount of eth, in wei, that is added to the penalty balance of the pod in case a validator's beacon chain balance ever falls
        below REQUIRED_BALANCE_GWEI

_currently this is set to REQUIRED_BALANCE_GWEI_

### REQUIRED_BALANCE_WEI

```solidity
function REQUIRED_BALANCE_WEI() external view returns (uint256)
```

The amount of eth, in wei, that is restaked per validator

### MIN_FULL_WITHDRAWAL_AMOUNT_GWEI

```solidity
function MIN_FULL_WITHDRAWAL_AMOUNT_GWEI() external view returns (uint64)
```

The amount of eth, in gwei, that can be part of a full withdrawal at the minimum

### validatorStatus

```solidity
function validatorStatus(uint40 validatorIndex) external view returns (enum IEigenPod.VALIDATOR_STATUS)
```

this is a mapping of validator indices to a Validator struct containing pertinent info about the validator

### getPartialWithdrawalClaim

```solidity
function getPartialWithdrawalClaim(uint256 index) external view returns (struct IEigenPod.PartialWithdrawalClaim)
```

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | struct IEigenPod.PartialWithdrawalClaim | claim is the partial withdrawal claim at the provided index |

### getPartialWithdrawalClaimsLength

```solidity
function getPartialWithdrawalClaimsLength() external view returns (uint256)
```

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| [0] | uint256 | length : the number of partial withdrawal claims ever made for this EigenPod |

### restakedExecutionLayerGwei

```solidity
function restakedExecutionLayerGwei() external view returns (uint64)
```

the amount of execution layer ETH in this contract that is staked in EigenLayer (i.e. withdrawn from beaconchain but not EigenLayer),

### instantlyWithdrawableBalanceGwei

```solidity
function instantlyWithdrawableBalanceGwei() external view returns (uint64)
```

the excess balance from full withdrawals over RESTAKED_BALANCE_PER_VALIDATOR or partial withdrawals

### rollableBalanceGwei

```solidity
function rollableBalanceGwei() external view returns (uint64)
```

the amount of penalties that have been paid from instantlyWithdrawableBalanceGwei or from partial withdrawals. These can be rolled
        over from restakedExecutionLayerGwei into instantlyWithdrawableBalanceGwei when all existing penalties have been paid

### penaltiesDueToOvercommittingGwei

```solidity
function penaltiesDueToOvercommittingGwei() external view returns (uint64)
```

the total amount of gwei outstanding (i.e. to-be-paid) penalties due to over committing to EigenLayer on behalf of this pod

### initialize

```solidity
function initialize(contract IEigenPodManager _eigenPodManager, address owner) external
```

Used to initialize the pointers to contracts crucial to the pod's functionality, in beacon proxy construction from EigenPodManager

### stake

```solidity
function stake(bytes pubkey, bytes signature, bytes32 depositDataRoot) external payable
```

Called by EigenPodManager when the owner wants to create another ETH validator.

### withdrawRestakedBeaconChainETH

```solidity
function withdrawRestakedBeaconChainETH(address recipient, uint256 amount) external
```

Transfers `amountWei` in ether from this contract to the specified `recipient` address
Called by EigenPodManager to withdrawBeaconChainETH that has been added to the EigenPod's balance due to a withdrawal from the beacon chain.

_Called during withdrawal or slashing.
Note that this function is marked as non-reentrant to prevent the recipient calling back into it_

### eigenPodManager

```solidity
function eigenPodManager() external view returns (contract IEigenPodManager)
```

The single EigenPodManager for EigenLayer

### podOwner

```solidity
function podOwner() external view returns (address)
```

The owner of this EigenPod

### verifyCorrectWithdrawalCredentials

```solidity
function verifyCorrectWithdrawalCredentials(uint40 validatorIndex, bytes proof, bytes32[] validatorFields) external
```

This function verifies that the withdrawal credentials of the podOwner are pointed to
this contract.  It verifies the provided proof of the ETH validator against the beacon chain state
root, marks the validator as 'active' in EigenLayer, and credits the restaked ETH in Eigenlayer.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| validatorIndex | uint40 |  |
| proof | bytes | is the bytes that prove the ETH validator's metadata against a beacon chain state root |
| validatorFields | bytes32[] | are the fields of the "Validator Container", refer to consensus specs  for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator |

### verifyOvercommittedStake

```solidity
function verifyOvercommittedStake(uint40 validatorIndex, bytes proof, bytes32[] validatorFields, uint256 beaconChainETHStrategyIndex) external
```

This function records an overcommitment of stake to EigenLayer on behalf of a certain ETH validator.
        If successful, the overcommitted balance is penalized (available for withdrawal whenever the pod's balance allows).
        The ETH validator's shares in the enshrined beaconChainETH strategy are also removed from the InvestmentManager and undelegated.

_For more details on the Beacon Chain spec, see: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| validatorIndex | uint40 |  |
| proof | bytes | is the bytes that prove the ETH validator's metadata against a beacon state root |
| validatorFields | bytes32[] | are the fields of the "Validator Container", refer to consensus specs |
| beaconChainETHStrategyIndex | uint256 | is the index of the beaconChainETHStrategy for the pod owner for the callback to                                     the InvestmentManger in case it must be removed from the list of the podOwners strategies |

### verifyBeaconChainFullWithdrawal

```solidity
function verifyBeaconChainFullWithdrawal(struct BeaconChainProofs.WithdrawalAndBlockNumberProof proof, bytes32 blockNumberRoot, bytes32[] withdrawalFields, uint256 beaconChainETHStrategyIndex) external
```

This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| proof | struct BeaconChainProofs.WithdrawalAndBlockNumberProof | is the information needed to check the veracity of the block number and withdrawal being proven |
| blockNumberRoot | bytes32 | is block number at which the withdrawal being proven is claimed to have happened |
| withdrawalFields | bytes32[] | are the fields of the withdrawal being proven |
| beaconChainETHStrategyIndex | uint256 | is the index of the beaconChainETHStrategy for the pod owner for the callback to                                     the EigenPodManager to the InvestmentManager in case it must be removed from the                                     podOwner's list of strategies |

### recordPartialWithdrawalClaim

```solidity
function recordPartialWithdrawalClaim(uint32 expireBlockNumber) external
```

This function records a balance snapshot for the EigenPod. Its main functionality is to begin an optimistic
        claim process on the partial withdrawable balance for the EigenPod owner. The owner is claiming that they have 
        proven all full withdrawals until block.number, allowing their partial withdrawal balance to be easily calculated 
        via  
             address(this).balance / GWEI_TO_WEI = 
                 restakedExecutionLayerGwei + 
                 instantlyWithdrawableBalanceGwei + 
                 partialWithdrawalsGwei
        If any other full withdrawals are proven to have happened before block.number, the partial withdrawal is marked as failed

_The sender should be able to safely set the value of `expireBlockNumber` to type(uint32).max if there are no pending full withdrawals to this Eigenpod._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| expireBlockNumber | uint32 | this is the block number before which the call to this function must be mined. To avoid race conditions with pending withdrawals,                          if there are any pending full withrawals to this Eigenpod, this parameter should be set to the blockNumber at which the next full withdrawal                          for a validator on this EigenPod is going to occur. |

### redeemLatestPartialWithdrawal

```solidity
function redeemLatestPartialWithdrawal(address recipient) external
```

This function allows pod owners to redeem their partial withdrawals after the fraudproof period has elapsed

### withdrawInstantlyWithdrawableBalanceGwei

```solidity
function withdrawInstantlyWithdrawableBalanceGwei(address recipient) external
```

Withdraws instantlyWithdrawableBalanceGwei to the specified `recipient`

_Note that this function is marked as non-reentrant to prevent the recipient calling back into it_

### rollOverRollableBalance

```solidity
function rollOverRollableBalance(uint64 amountGwei) external
```

Rebalances restakedExecutionLayerGwei in case penalties were previously paid from instantlyWithdrawableBalanceGwei or partial 
        withdrawal, so the EigenPod thinks podOwner has more restakedExecutionLayerGwei and staked balance than beaconChainETH on EigenLayer

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountGwei | uint64 | is the amount, in gwei, to roll over |

### payOffPenalties

```solidity
function payOffPenalties() external
```

Pays off existing penalties due to overcommitting to EigenLayer. Funds for paying penalties are deducted:
        1) first, from the execution layer ETH that is restaked in EigenLayer, because 
           it is the ETH that is actually supposed to be restaked
        2) second, from the instantlyWithdrawableBalanceGwei, to avoid allowing instant withdrawals
           from instantlyWithdrawableBalanceGwei, in case the balance of the contract is not enough 
           to cover the entire penalty

