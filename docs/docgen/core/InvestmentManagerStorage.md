# Solidity API

## InvestmentManagerStorage

This storage contract is separate from the logic to simplify the upgrade process.

### DOMAIN_TYPEHASH

```solidity
bytes32 DOMAIN_TYPEHASH
```

The EIP-712 typehash for the contract's domain

### DEPOSIT_TYPEHASH

```solidity
bytes32 DEPOSIT_TYPEHASH
```

The EIP-712 typehash for the deposit struct used by the contract

### DOMAIN_SEPARATOR

```solidity
bytes32 DOMAIN_SEPARATOR
```

EIP-712 Domain separator

### nonces

```solidity
mapping(address => uint256) nonces
```

### MAX_INVESTOR_STRATS_LENGTH

```solidity
uint8 MAX_INVESTOR_STRATS_LENGTH
```

### delegation

```solidity
contract IEigenLayerDelegation delegation
```

Returns the single, central Delegation contract of EigenLayer

### eigenPodManager

```solidity
contract IEigenPodManager eigenPodManager
```

### slasher

```solidity
contract ISlasher slasher
```

Returns the single, central Slasher contract of EigenLayer

### strategyWhitelister

```solidity
address strategyWhitelister
```

Permissioned role, which can be changed by the contract owner. Has the ability to edit the strategy whitelist

### withdrawalDelayBlocks

```solidity
uint256 withdrawalDelayBlocks
```

Minimum delay enforced by this contract for completing queued withdrawals. Measured in blocks, and adjustable by this contract's owner,
up to a maximum of `MAX_WITHDRAWAL_DELAY_BLOCKS`. Minimum value is 0 (i.e. no delay enforced).

_Note that the withdrawal delay is not enforced on withdrawals of 'beaconChainETH', as the EigenPods have their own separate delay mechanic
and we want to avoid stacking multiple enforced delays onto a single withdrawal._

### MAX_WITHDRAWAL_DELAY_BLOCKS

```solidity
uint256 MAX_WITHDRAWAL_DELAY_BLOCKS
```

### investorStratShares

```solidity
mapping(address => mapping(contract IInvestmentStrategy => uint256)) investorStratShares
```

Mapping: staker => InvestmentStrategy => number of shares which they currently hold

### investorStrats

```solidity
mapping(address => contract IInvestmentStrategy[]) investorStrats
```

Mapping: staker => array of strategies in which they have nonzero shares

### withdrawalRootPending

```solidity
mapping(bytes32 => bool) withdrawalRootPending
```

Mapping: hash of withdrawal inputs, aka 'withdrawalRoot' => whether the withdrawal is pending

### numWithdrawalsQueued

```solidity
mapping(address => uint256) numWithdrawalsQueued
```

Mapping: staker => cumulative number of queued withdrawals they have ever initiated. only increments (doesn't decrement)

### strategyIsWhitelistedForDeposit

```solidity
mapping(contract IInvestmentStrategy => bool) strategyIsWhitelistedForDeposit
```

Mapping: strategy => whether or not stakers are allowed to deposit into it

### beaconChainETHWithdrawalDebt

```solidity
mapping(address => uint256) beaconChainETHWithdrawalDebt
```

### beaconChainETHStrategy

```solidity
contract IInvestmentStrategy beaconChainETHStrategy
```

returns the enshrined beaconChainETH Strategy

### constructor

```solidity
constructor(contract IEigenLayerDelegation _delegation, contract IEigenPodManager _eigenPodManager, contract ISlasher _slasher) internal
```

