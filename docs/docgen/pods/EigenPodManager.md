# Solidity API

## EigenPodManager

The main functionalities are:
- creating EigenPods
- staking for new validators on EigenPods
- keeping track of the balances of all validators of EigenPods, and their stake in EigenLayer
- withdrawing eth when withdrawals are initiated

### ethPOS

```solidity
contract IETHPOSDeposit ethPOS
```

### eigenPodBeacon

```solidity
contract IBeacon eigenPodBeacon
```

Beacon proxy to which the EigenPods point

### investmentManager

```solidity
contract IInvestmentManager investmentManager
```

EigenLayer's InvestmentManager contract

### slasher

```solidity
contract ISlasher slasher
```

EigenLayer's Slasher contract

### beaconChainOracle

```solidity
contract IBeaconChainOracle beaconChainOracle
```

Oracle contract that provides updates to the beacon chain's state

### podOwnerToUnwithdrawnPaidPenalties

```solidity
mapping(address => uint256) podOwnerToUnwithdrawnPaidPenalties
```

Pod owner to the amount of penalties they have paid that are still in this contract

### BeaconOracleUpdated

```solidity
event BeaconOracleUpdated(address newOracleAddress)
```

Emitted to notify the update of the beaconChainOracle address

### PodDeployed

```solidity
event PodDeployed(address eigenPod, address podOwner)
```

Emitted to notify the deployment of an EigenPod

### BeaconChainETHDeposited

```solidity
event BeaconChainETHDeposited(address podOwner, uint256 amount)
```

Emitted to notify a deposit of beacon chain ETH recorded in the investment manager

### PenaltiesPaid

```solidity
event PenaltiesPaid(address podOwner, uint256 amountPaid)
```

Emitted when an EigenPod pays penalties, on behalf of its owner

### onlyEigenPod

```solidity
modifier onlyEigenPod(address podOwner)
```

### onlyInvestmentManager

```solidity
modifier onlyInvestmentManager()
```

### constructor

```solidity
constructor(contract IETHPOSDeposit _ethPOS, contract IBeacon _eigenPodBeacon, contract IInvestmentManager _investmentManager, contract ISlasher _slasher) public
```

### initialize

```solidity
function initialize(contract IBeaconChainOracle _beaconChainOracle, address initialOwner) public
```

### createPod

```solidity
function createPod() external
```

Creates an EigenPod for the sender.

_Function will revert if the `msg.sender` already has an EigenPod._

### stake

```solidity
function stake(bytes pubkey, bytes signature, bytes32 depositDataRoot) external payable
```

Stakes for a new beacon chain validator on the sender's EigenPod. 
Also creates an EigenPod for the sender if they don't have one already.

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| pubkey | bytes | The 48 bytes public key of the beacon chain validator. |
| signature | bytes | The validator's signature of the deposit data. |
| depositDataRoot | bytes32 | The root/hash of the deposit data for the validator's deposit. |

### restakeBeaconChainETH

```solidity
function restakeBeaconChainETH(address podOwner, uint256 amount) external
```

Deposits/Restakes beacon chain ETH in EigenLayer on behalf of the owner of an EigenPod.

_Callable only by the podOwner's EigenPod contract._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| podOwner | address | The owner of the pod whose balance must be deposited. |
| amount | uint256 | The amount of ETH to 'deposit' (i.e. be credited to the podOwner). |

### recordOvercommittedBeaconChainETH

```solidity
function recordOvercommittedBeaconChainETH(address podOwner, uint256 beaconChainETHStrategyIndex, uint256 amount) external
```

Removes beacon chain ETH from EigenLayer on behalf of the owner of an EigenPod, when the
        balance of a validator is lower than how much stake they have committed to EigenLayer

_Callable only by the podOwner's EigenPod contract._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| podOwner | address | The owner of the pod whose balance must be removed. |
| beaconChainETHStrategyIndex | uint256 |  |
| amount | uint256 | The amount of beacon chain ETH to decrement from the podOwner's shares in the investmentManager. |

### withdrawRestakedBeaconChainETH

```solidity
function withdrawRestakedBeaconChainETH(address podOwner, address recipient, uint256 amount) external
```

Withdraws ETH from an EigenPod. The ETH must have first been withdrawn from the beacon chain.

_Callable only by the InvestmentManager contract._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| podOwner | address | The owner of the pod whose balance must be withdrawn. |
| recipient | address | The recipient of the withdrawn ETH. |
| amount | uint256 | The amount of ETH to withdraw. |

### payPenalties

```solidity
function payPenalties(address podOwner) external payable
```

Records receiving ETH from the `PodOwner`'s EigenPod, paid in order to fullfill the EigenPod's penalties to EigenLayer

_Callable only by the podOwner's EigenPod contract._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| podOwner | address | The owner of the pod whose balance is being sent. |

### withdrawPenalties

```solidity
function withdrawPenalties(address podOwner, address recipient, uint256 amount) external
```

Withdraws paid penalties of the `podOwner`'s EigenPod, to the `recipient` address

_Callable only by the investmentManager.owner()._

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| podOwner | address |  |
| recipient | address | The recipient of withdrawn ETH. |
| amount | uint256 | The amount of ETH to withdraw. |

### updateBeaconChainOracle

```solidity
function updateBeaconChainOracle(contract IBeaconChainOracle newBeaconChainOracle) external
```

Updates the oracle contract that provides the beacon chain state root

_Callable only by the owner of this contract (i.e. governance)_

#### Parameters

| Name | Type | Description |
| ---- | ---- | ----------- |
| newBeaconChainOracle | contract IBeaconChainOracle | is the new oracle contract being pointed to |

### _deployPod

```solidity
function _deployPod() internal returns (contract IEigenPod)
```

### _updateBeaconChainOracle

```solidity
function _updateBeaconChainOracle(contract IBeaconChainOracle newBeaconChainOracle) internal
```

### getPod

```solidity
function getPod(address podOwner) public view returns (contract IEigenPod)
```

Returns the address of the `podOwner`'s EigenPod (whether it is deployed yet or not).

### hasPod

```solidity
function hasPod(address podOwner) public view returns (bool)
```

Returns 'true' if the `podOwner` has created an EigenPod, and 'false' otherwise.

### getBeaconChainStateRoot

```solidity
function getBeaconChainStateRoot() external view returns (bytes32)
```

Returns the latest beacon chain state root posted to the beaconChainOracle.

