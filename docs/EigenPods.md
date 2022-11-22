
# EigenPods: Handling Beacon Chain ETH

## Overview

This writeup serves to explain our initial design for handling beacon chain ETH being staked on EigenLayer.

It is important to note that we will likely be integrating with liquid staking protocols (particularly Rocket Pool) "above the hood", meaning that withdrawal credentials will be pointed to EigenLayer at the smart contract layer rather than the consensus layer. This is because liquid staking protocols need their contracts to be in possession of the withdrawal credentials in order to not have platform risk on EigenLayer. If they are willing to work with us, we can create a bespoke solution, but this will likely be solved permissionlessly, over the hood. Although this adds risk on the functionality of the underlying liquid staking protocol, this is likely negligible.

This post is purely to explain how EigenLayer will handle beacon chain validators with their withdrawal credentials pointed directly to the EigenLayer contracts, i.e. "solo stakers".

## Introducing: The EigenPod

Similar to RocketPool, we will have an EigenPodManager, which ETH2 validators will use when they want to stake and restake their beaconchain balance on EigenLayer. This call will deploy a contract,  called an EigenPod, which will manage withdrawals and slashing for that validator. The pod allows stakers to initiate their deposit into the beacon chain and point their withdrawal credentials to the EigenPod using the `stake()` function.
To handle upgradability for the EigenPods as withdrawal specs get cleared up, we will use the beacon proxy pattern so EigenPods will simply read their implementation contract's address from an upgradable beacon and delegate call to the retrieved address.


## How to Use EigenPods 

### Staking Beacon Chain ETH via an EigenPod
In order to stake in the Beacon Chain with EigenLayer, a staker can call the `stake()` function in the `EigenPodManager`. 
```solidity
    function stake(
        bytes calldata pubkey, 
        bytes calldata signature, 
        bytes32 depositDataRoot
    ) external payable
```
This function deploys an `EigenPod` contract and inititates a Beacon Chain deposit with the provided validator pubkey and signature.  

## Proving Beacon Chain Balance
Validators will prove their withdrawal credentials are pointed to their EigenPod against the most recent state root posted by the oracle via a merkle proof. We will also have an oracle that may also submit balance updates via merkle proofs (or perhaps via authority) for any validators that are slashed. These proofs are in the form of an enshrined "beaconChainETH" strategy.  This verification is done via the `verifyCorrectWithdrawalCredentials` function:

```solidity
function verifyCorrectWithdrawalCredentials(
        bytes calldata pubkey, 
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external {
```
### Restaking Beacon Chain ETH
Once a staker has deployed an EigenPod and initiated a Beacon Chain deposit, they have the option to restake their deposit via EigenLayer by calling the `restakeBeaconChainETH` function.  It is important to note that this function simply accounts for the beacon chain ETH in the InvestmentManager, but does not actively delegate that stake.  

```solidity
    function restakeBeaconChainETH(
        address podOwner, 
        uint128 amount
    ) external onlyInvestmentManager
```

## Withdrawals

Whenever a validator triggers a withdrawal (as of now this is from the validating keys) their EigenPod's balance will eventually increase by the amount withdrawn. At that point, the validator will prove their withdrawal against the beacon chain state root via the `verifyBalanceUpdate` function:
```solidity
function verifyBalanceUpdate(
        bytes calldata pubkey, 
        bytes32 beaconStateRoot, 
        bytes calldata proofs, 
        bytes32[] calldata validatorFields
    ) external
```
This function will ensure that the staker's `EigenPodManager` balance is updated correctly.  The validator will withdraw via the withdrawal flow housed in the `InvestmentManager`.  

**It is important to note that after withdrawal, if a staker who is staked in EigenLayer chooses to restake once again into eigenlayer before their stakes are updated (to reflect the initial withdrawal), they will get frozen.**

If an EigenPod user slashed on the Beacon Chain, anyone can optimistically call the `eigenPodManager.verifyBalanceUpdate()` to prove that the user has been slashed. This will trigger a call to the `EigenPodManager.updateBeaconChainBalance()` function which checks that `depositedBalance > newBalance`. Here `depositedBalance` is the amount of beacon chain balance that is accounted for in the InvestmentManager and `newBalance` would is the new, slashed beacon chain balance.  If slashed, then `depositedBalance` is indeed greater than `newBalance`, and the user "under-collateralized". Thus, they will be frozen.  

## The Oracle

TBD
