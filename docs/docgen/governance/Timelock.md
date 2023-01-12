# Solidity API

## Timelock

### NewAdmin

```solidity
event NewAdmin(address newAdmin)
```

### NewPendingAdmin

```solidity
event NewPendingAdmin(address newPendingAdmin)
```

### NewDelay

```solidity
event NewDelay(uint256 newDelay)
```

### CancelTransaction

```solidity
event CancelTransaction(bytes32 txHash, address target, uint256 value, string signature, bytes data, uint256 eta)
```

### ExecuteTransaction

```solidity
event ExecuteTransaction(bytes32 txHash, address target, uint256 value, string signature, bytes data, uint256 eta)
```

### QueueTransaction

```solidity
event QueueTransaction(bytes32 txHash, address target, uint256 value, string signature, bytes data, uint256 eta)
```

### GRACE_PERIOD

```solidity
uint256 GRACE_PERIOD
```

### MINIMUM_DELAY

```solidity
uint256 MINIMUM_DELAY
```

### MAXIMUM_DELAY

```solidity
uint256 MAXIMUM_DELAY
```

### admin

```solidity
address admin
```

### pendingAdmin

```solidity
address pendingAdmin
```

### delay

```solidity
uint256 delay
```

### queuedTransactions

```solidity
mapping(bytes32 => bool) queuedTransactions
```

### constructor

```solidity
constructor(address admin_, uint256 delay_) public
```

### fallback

```solidity
fallback() external payable
```

### receive

```solidity
receive() external payable
```

### setDelay

```solidity
function setDelay(uint256 delay_) external
```

### acceptAdmin

```solidity
function acceptAdmin() external
```

### setPendingAdmin

```solidity
function setPendingAdmin(address pendingAdmin_) external
```

### queueTransaction

```solidity
function queueTransaction(address target, uint256 value, string signature, bytes data, uint256 eta) external returns (bytes32)
```

### cancelTransaction

```solidity
function cancelTransaction(address target, uint256 value, string signature, bytes data, uint256 eta) external
```

### executeTransaction

```solidity
function executeTransaction(address target, uint256 value, string signature, bytes data, uint256 eta) external payable returns (bytes)
```
