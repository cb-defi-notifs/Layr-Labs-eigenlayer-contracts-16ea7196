# Solidity API

## BeaconChainProofs

### NUM_BEACON_BLOCK_HEADER_FIELDS

```solidity
uint256 NUM_BEACON_BLOCK_HEADER_FIELDS
```

### BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT

```solidity
uint256 BEACON_BLOCK_HEADER_FIELD_TREE_HEIGHT
```

### NUM_BEACON_STATE_FIELDS

```solidity
uint256 NUM_BEACON_STATE_FIELDS
```

### BEACON_STATE_FIELD_TREE_HEIGHT

```solidity
uint256 BEACON_STATE_FIELD_TREE_HEIGHT
```

### NUM_ETH1_DATA_FIELDS

```solidity
uint256 NUM_ETH1_DATA_FIELDS
```

### ETH1_DATA_FIELD_TREE_HEIGHT

```solidity
uint256 ETH1_DATA_FIELD_TREE_HEIGHT
```

### NUM_VALIDATOR_FIELDS

```solidity
uint256 NUM_VALIDATOR_FIELDS
```

### VALIDATOR_FIELD_TREE_HEIGHT

```solidity
uint256 VALIDATOR_FIELD_TREE_HEIGHT
```

### NUM_EXECUTION_PAYLOAD_HEADER_FIELDS

```solidity
uint256 NUM_EXECUTION_PAYLOAD_HEADER_FIELDS
```

### EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT

```solidity
uint256 EXECUTION_PAYLOAD_HEADER_FIELD_TREE_HEIGHT
```

### HISTORICAL_ROOTS_TREE_HEIGHT

```solidity
uint256 HISTORICAL_ROOTS_TREE_HEIGHT
```

### HISTORICAL_BATCH_TREE_HEIGHT

```solidity
uint256 HISTORICAL_BATCH_TREE_HEIGHT
```

### STATE_ROOTS_TREE_HEIGHT

```solidity
uint256 STATE_ROOTS_TREE_HEIGHT
```

### NUM_WITHDRAWAL_FIELDS

```solidity
uint256 NUM_WITHDRAWAL_FIELDS
```

### WITHDRAWAL_FIELD_TREE_HEIGHT

```solidity
uint256 WITHDRAWAL_FIELD_TREE_HEIGHT
```

### VALIDATOR_TREE_HEIGHT

```solidity
uint256 VALIDATOR_TREE_HEIGHT
```

### WITHDRAWALS_TREE_HEIGHT

```solidity
uint256 WITHDRAWALS_TREE_HEIGHT
```

### STATE_ROOT_INDEX

```solidity
uint256 STATE_ROOT_INDEX
```

### PROPOSER_INDEX_INDEX

```solidity
uint256 PROPOSER_INDEX_INDEX
```

### STATE_ROOTS_INDEX

```solidity
uint256 STATE_ROOTS_INDEX
```

### HISTORICAL_ROOTS_INDEX

```solidity
uint256 HISTORICAL_ROOTS_INDEX
```

### ETH_1_ROOT_INDEX

```solidity
uint256 ETH_1_ROOT_INDEX
```

### VALIDATOR_TREE_ROOT_INDEX

```solidity
uint256 VALIDATOR_TREE_ROOT_INDEX
```

### EXECUTION_PAYLOAD_HEADER_INDEX

```solidity
uint256 EXECUTION_PAYLOAD_HEADER_INDEX
```

### HISTORICAL_BATCH_STATE_ROOT_INDEX

```solidity
uint256 HISTORICAL_BATCH_STATE_ROOT_INDEX
```

### VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX

```solidity
uint256 VALIDATOR_WITHDRAWAL_CREDENTIALS_INDEX
```

### VALIDATOR_BALANCE_INDEX

```solidity
uint256 VALIDATOR_BALANCE_INDEX
```

### BLOCK_NUMBER_INDEX

```solidity
uint256 BLOCK_NUMBER_INDEX
```

### WITHDRAWALS_ROOT_INDEX

```solidity
uint256 WITHDRAWALS_ROOT_INDEX
```

### WITHDRAWAL_VALIDATOR_INDEX_INDEX

```solidity
uint256 WITHDRAWAL_VALIDATOR_INDEX_INDEX
```

### WITHDRAWAL_VALIDATOR_AMOUNT_INDEX

```solidity
uint256 WITHDRAWAL_VALIDATOR_AMOUNT_INDEX
```

### HISTORICALBATCH_STATEROOTS_INDEX

```solidity
uint256 HISTORICALBATCH_STATEROOTS_INDEX
```

### WithdrawalAndBlockNumberProof

```solidity
struct WithdrawalAndBlockNumberProof {
  uint16 stateRootIndex;
  bytes32 executionPayloadHeaderRoot;
  bytes executionPayloadHeaderProof;
  uint8 withdrawalIndex;
  bytes withdrawalProof;
  bytes blockNumberProof;
}
```

### computePhase0BeaconBlockHeaderRoot

```solidity
function computePhase0BeaconBlockHeaderRoot(bytes32[5] blockHeaderFields) internal pure returns (bytes32)
```

### computePhase0BeaconStateRoot

```solidity
function computePhase0BeaconStateRoot(bytes32[21] beaconStateFields) internal pure returns (bytes32)
```

### computePhase0ValidatorRoot

```solidity
function computePhase0ValidatorRoot(bytes32[8] validatorFields) internal pure returns (bytes32)
```

### computePhase0Eth1DataRoot

```solidity
function computePhase0Eth1DataRoot(bytes32[3] eth1DataFields) internal pure returns (bytes32)
```

### verifyValidatorFields

```solidity
function verifyValidatorFields(uint40 validatorIndex, bytes32 beaconStateRoot, bytes proof, bytes32[] validatorFields) internal view
```

This function verifies merkle proofs the fields of a certain validator against a beacon chain state root

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| validatorIndex | uint40 | the index of the proven validator |
| beaconStateRoot | bytes32 | is the beacon chain state root. |
| proof | bytes | is the data used in proving the validator's fields |
| validatorFields | bytes32[] | the claimed fields of the validator |

### verifyWithdrawalFieldsAndBlockNumber

```solidity
function verifyWithdrawalFieldsAndBlockNumber(bytes32 beaconStateRoot, struct BeaconChainProofs.WithdrawalAndBlockNumberProof proof, bytes32 blockNumberRoot, bytes32[] withdrawalFields) internal view
```

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| beaconStateRoot | bytes32 | is the latest beaconStateRoot posted by the oracle |
| proof | struct BeaconChainProofs.WithdrawalAndBlockNumberProof |  |
| blockNumberRoot | bytes32 |  |
| withdrawalFields | bytes32[] |  |

