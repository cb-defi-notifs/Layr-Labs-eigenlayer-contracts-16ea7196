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

### beaconChainETHStrategy

```solidity
contract IInvestmentStrategy beaconChainETHStrategy
```

returns the enshrined beaconChainETH Strategy

### constructor

```solidity
constructor(contract IEigenLayerDelegation _delegation, contract IEigenPodManager _eigenPodManager, contract ISlasher _slasher) internal
```

