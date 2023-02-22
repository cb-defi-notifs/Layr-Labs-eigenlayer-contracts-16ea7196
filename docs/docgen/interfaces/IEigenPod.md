# Solidity API

## IEigenPod

The main functionalities are:
- creating new ETH validators with their withdrawal credentials pointed to this contract
- proving from beacon chain state roots that withdrawal credentials are pointed to this contract
- proving from beacon chain state roots the balances of ETH validators with their withdrawal credentials
  pointed to this contract
- updating aggregate balances in the EigenPodManager
- withdrawing eth when withdrawals are initiated

_Note that all beacon chain balances are stored as gwei within the beacon chain datastructures. We choose
  to account balances in terms of gwei in the EigenPod contract and convert to wei when making calls to other contracts_

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
function verifyCorrectWithdrawalCredentials(uint64 slot, uint40 validatorIndex, bytes proof, bytes32[] validatorFields) external
```

This function verifies that the withdrawal credentials of the podOwner are pointed to
this contract. It verifies the provided proof of the ETH validator against the beacon chain state
root, marks the validator as 'active' in EigenLayer, and credits the restaked ETH in Eigenlayer.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| slot | uint64 | The Beacon Chain slot whose state root the `proof` will be proven against. |
| validatorIndex | uint40 |  |
| proof | bytes | is the bytes that prove the ETH validator's metadata against a beacon chain state root |
| validatorFields | bytes32[] | are the fields of the "Validator Container", refer to consensus specs  for details: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator |

### verifyOvercommittedStake

```solidity
function verifyOvercommittedStake(uint64 slot, uint40 validatorIndex, bytes proof, bytes32[] validatorFields, uint256 beaconChainETHStrategyIndex) external
```

This function records an overcommitment of stake to EigenLayer on behalf of a certain ETH validator.
        If successful, the overcommitted balance is penalized (available for withdrawal whenever the pod's balance allows).
        The ETH validator's shares in the enshrined beaconChainETH strategy are also removed from the InvestmentManager and undelegated.

_For more details on the Beacon Chain spec, see: https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#validator_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| slot | uint64 | The Beacon Chain slot whose state root the `proof` will be proven against. |
| validatorIndex | uint40 |  |
| proof | bytes | is the bytes that prove the ETH validator's metadata against a beacon state root |
| validatorFields | bytes32[] | are the fields of the "Validator Container", refer to consensus specs |
| beaconChainETHStrategyIndex | uint256 | is the index of the beaconChainETHStrategy for the pod owner for the callback to                                     the InvestmentManger in case it must be removed from the list of the podOwners strategies |

### verifyBeaconChainFullWithdrawal

```solidity
function verifyBeaconChainFullWithdrawal(uint64 slot, struct BeaconChainProofs.WithdrawalAndBlockNumberProof proof, bytes32 blockNumberRoot, bytes32[] withdrawalFields, uint256 beaconChainETHStrategyIndex) external
```

This function records a full withdrawal on behalf of one of the Ethereum validators for this EigenPod

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| slot | uint64 | The Beacon Chain slot whose state root the `proof` will be proven against. |
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

