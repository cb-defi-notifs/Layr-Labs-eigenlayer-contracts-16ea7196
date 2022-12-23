# Solidity API

## AaveInvestmentStrategy_STETH

Passively lends tokens on AAVE. Does not perform any borrowing.

_This contract is designed to accept deposits and process withdrawals in *either* the underlyingToken or aTokens
This contract uses LIDO's StableSwapStateOracle to determine the current stETH/ETH ratio -- see https://docs.lido.fi/contracts/stable-swap-state-oracle
The StableSwapStateOracle on Mainnet is here https://etherscan.io/address/0x3a6bd15abf19581e411621d669b6a2bbe741ffd6#readContract_

### stableSwapOracle

```solidity
contract IStableSwapStateOracle stableSwapOracle
```

### constructor

```solidity
constructor(contract IInvestmentManager _investmentManager) public
```

### initialize

```solidity
function initialize(contract IERC20 _underlyingToken, contract ILendingPool _lendingPool, contract IERC20 _aToken, contract IStableSwapStateOracle _stableSwapOracle, contract IPauserRegistry _pauserRegistry) external
```

### sharesToUnderlyingView

```solidity
function sharesToUnderlyingView(uint256 amountShares) public view returns (uint256)
```

Used to convert a number of shares to the equivalent amount of underlying tokens for this strategy.
This strategy uses LIDO's `stableSwapOracle` to estimate the conversion from stETH to ETH.
In contrast to `sharesToUnderlying`, this function guarantees no state modifications

_Implementation for these functions in particular may vary signifcantly for different strategies_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountShares | uint256 | is the amount of shares to calculate its conversion into the underlying token |

### underlyingToSharesView

```solidity
function underlyingToSharesView(uint256 amountUnderlying) public view returns (uint256)
```

Used to convert an amount of underlying tokens to the equivalent amount of shares in this strategy.
This strategy uses LIDO's `stableSwapOracle` to estimate the conversion from ETH to stETH.
In contrast to `underlyingToShares`, this function guarantees no state modifications

_Implementation for these functions in particular may vary signifcantly for different strategies_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| amountUnderlying | uint256 | is the amount of `underlyingToken` to calculate its conversion into strategy shares |

