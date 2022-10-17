---
title: EigenPods Overview
tags: high-level-docs
---

# EigenPods: Handling Beacon Chain ETH

## Overview

This writeup serves to explain our initial design for handling beacon chain ETH being staked on EigenLayer.

It is important to note that we will likely be integrating with liquid staking protocols (particularly Rocket Pool) "above the hood", meaning that withdrawal credentials will be pointed to EigenLayer at the smart contract layer rather than the consensus layer. This is because liquid staking protocols need their contracts to be in possession of the withdrawal credentials in order to not have platform risk on EigenLayer. If they are willing to work with us, we can create a bespoke solution, but this will likely be solved permissionlessly, over the hood. Although this adds risk on the functionality of the underlying liquid staking protocol, this is likely negligible.

This post is purely to explain how EigenLayer will handle beacon chain validators with their withdrawal credentials pointed directly to the EigenLayer contracts, i.e. "solo stakers".

## The EigenPod

Similar to RocketPool, we will have an EigenPodManager, which ETH2 validators will use when they want to stake and restake their beaconchain balance on EigenLayer. This call will deploy a contract, tentatively called an EigenPod, which will manage withdrawals and slashing for that validator. It will initiate their deposit into the beacon chain and point their withdrawal credentials to the EigenPod. To handle upgradability for the EigenPods as withdrawal specs get cleared up, we will use the beacon proxy pattern so EigenPods will simply read their implementation contract's address from an upgradable beacon and delegate call to the retrieved address.

## The Oracle

Either we will have an oracle or we will use Rocket pool's oracle to bring beacon chain state roots into the EVM. 

## Proving balances

Validators will prove their withdrawal credentials are pointed to their EigenPod against the most recent state root posted by the oracle via a merkle proof. We will also have an oracle that may also submit balance updates via merkle proofs (or perhaps via authority) for any validators that are slashed. These proofs will likely be to an enshrined "beacon chain eth" strategy.

## Weighing functions

~~Weighing functions will now need to look up user specific shares from this strategy when weighing ETH rather than looking at "shares" in the investment manager due to the way updates will work. This is a little wonky and could perhaps be improved by not storing shares in the investment manager at all and just calling the underlying strategy whenever the number of shares is desired? @Nz0kioR5Rwy55jHlaAUhzQ pls weigh in on this and help w impl~~

Update:

After a chat with Jeff, a proposal for the design is to have a separate BeaconChainETH manager than handles all ops related to solo staking on EigenLayer (deposits, withdrawals, delegation), and an enshrined strategy address in EigenLayerDelegation that keeps track of the amount of beaconchaineth delegated to different operators.

## Withdrawals

Whenever a validator triggers a withdrawal (as of now this is from the validating keys) their EigenPod's balance will eventually increase by the amount withdrawn. At that point, the validator will prove their withdrawal against the beacon chain state root and initiate the withdrawal process on the BeaconChainETH contracts before their EigenPod allows them to withdraw the ETH.  It is important to note that after withdrawal, if a staker chooses to restake into eigenlayer before updating their stakes (to reflect the withdrawal), they will get frozen.  

# Work

## Contracts
Gautham (third person giga yeet) can do the initial impl of EigenPod+Oracle Stub+Proving Balances. Jeffrey and him can work together on modifying weighting functions. Gautham can also do the initial impl of withdrawals. 

## Off chain
We will need a CLI to be used for staking via EigenPods. This design can be heavily informed from and perhaps forked from RocketPool's stake CLI. Gautham will lead dev on this and along with help from one of the offchain peeps who is interested in Ethereum beacon chain shit. Just LMK.

