# Solidity API

## IDelegationTerms

The gas budget provided to this contract in calls from EigenLayr contracts is limited.

### payForService

```solidity
function payForService(contract IERC20 token, uint256 amount) external payable
```

### onDelegationWithdrawn

```solidity
function onDelegationWithdrawn(address delegator, contract IInvestmentStrategy[] investorStrats, uint256[] investorShares) external
```

### onDelegationReceived

```solidity
function onDelegationReceived(address delegator, contract IInvestmentStrategy[] investorStrats, uint256[] investorShares) external
```

