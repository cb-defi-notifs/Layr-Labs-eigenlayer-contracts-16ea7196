# Solidity API

## AaveInvestmentStrategy

Passively lends tokens on AAVE. Does not perform any borrowing.

_This contract is designed to accept deposits and process withdrawals in *either* the underlyingToken or aTokens_

### lendingPool

```solidity
contract ILendingPool lendingPool
```

### aToken

```solidity
contract IERC20 aToken
```

### constructor

```solidity
constructor(contract IInvestmentManager _investmentManager) internal
```

### initialize

```solidity
function initialize(contract IERC20 _underlyingToken, contract ILendingPool _lendingPool, contract IERC20 _aToken, contract IPauserRegistry _pauserRegistry) public
```

### deposit

```solidity
function deposit(contract IERC20 token, uint256 amount) external returns (uint256 newShares)
```

Used to deposit tokens into this InvestmentStrategy
This strategy accepts deposits either in the form of `underlyingToken` OR `aToken`

_This function is only callable by the investmentManager contract. It is invoked inside of the investmentManager's
`depositIntoStrategy` function, and individual share balances are recorded in the investmentManager as well_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| token | contract IERC20 | is the ERC20 token being deposited |
| amount | uint256 | is the amount of token being deposited |

#### Return Values

| Name | Type | Description |
| ---- | ---- | ----------- |
| newShares | uint256 | is the number of new shares issued at the current exchange ratio. For this strategy, the exchange ratio is fixed at (1 underlying token) / (1 share) due to the nature of AAVE's ATokens. |

### withdraw

```solidity
function withdraw(address depositor, contract IERC20 token, uint256 shareAmount) external
```

Used to withdraw tokens from this InvestmentStrategy, to the `depositor`'s address
This strategy distributes withdrawals either in the form of `underlyingToken` OR `aToken`

_This function is only callable by the investmentManager contract. It is invoked inside of the investmentManager's
other functions, and individual share balances are recorded in the investmentManager as well_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| depositor | address |  |
| token | contract IERC20 | is the ERC20 token being transferred out |
| shareAmount | uint256 | is the amount of shares being withdrawn |

### explanation

```solidity
function explanation() external pure returns (string)
```

Currently returns a brief string explaining the strategy's goal & purpose, but for more complex
strategies, may be a link to metadata that explains in more detail.

### _tokenBalance

```solidity
function _tokenBalance() internal view returns (uint256)
```

Internal function used to fetch this contract's current balance of `aToken`.

