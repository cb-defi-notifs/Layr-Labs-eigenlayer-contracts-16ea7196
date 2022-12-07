
# EigenPods: Handling Beacon Chain ETH

## Overview

This document explains *EigenPods*, the mechanism by which EigenLayer facilitates the restaking of native beacon chain ether.

It is important to contrast this with the restaking of liquid staking derivatives (LSDs) on EigenLayer. EigenLayer will integrate with liquid staking protocols "above the hood", meaning that withdrawal credentials will be pointed to EigenLayer at the smart contract layer rather than the consensus layer. This is because liquid staking protocols need their contracts to be in possession of the withdrawal credentials in order to not have platform risk on EigenLayer. As always, this means that value of liquid staking derivatives carries a discount due to additional smart contract risk.

The architechtural design of the EigenPods system is inspired by various liquid staking protocols, particularly Rocket Pool 🚀.

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
This function deploys an `EigenPod` for the caller if they don't have one already and inititates a deposit of 32 ETH to the Beacon Chain deposit contracts, with the provided parameters.  

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

If an EigenPod user slashed on the Beacon Chain, anyone can call the `eigenPodManager.verifyBalanceUpdate()` to prove that the user has been slashed (this is done by any party, optimistically. we will run an updater). This will trigger a call to the `EigenPodManager.updateBeaconChainBalance()` function which checks that `depositedBalance > newBalance`. Here `depositedBalance` is the amount of beacon chain balance that is accounted for in the InvestmentManager and `newBalance` would is the new, slashed beacon chain balance.  If slashed, then `depositedBalance` is indeed greater than `newBalance`, and the user "under-collateralized". Thus, they will be frozen.  

## The Oracle

TBD
