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

Returns the current shares of `user` in `strategy`

### investorStrats

```solidity
mapping(address => contract IInvestmentStrategy[]) investorStrats
```

### withdrawalRootPending

```solidity
mapping(bytes32 => bool) withdrawalRootPending
```

### numWithdrawalsQueued

```solidity
mapping(address => uint256) numWithdrawalsQueued
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

