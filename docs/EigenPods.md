
# EigenPods: Handling Beacon Chain ETH

## Overview

This document explains *EigenPods*, the mechanism by which EigenLayer facilitates the restaking of native beacon chain ether.

It is important to contrast this with the restaking of liquid staking derivatives (LSDs) on EigenLayer. EigenLayer will integrate with liquid staking protocols "above the hood", meaning that withdrawal credentials will be pointed to EigenLayer at the smart contract layer rather than the consensus layer. This is because liquid staking protocols need their contracts to be in possession of the withdrawal credentials in order to not have platform risk on EigenLayer. As always, this means that value of liquid staking derivatives carries a discount due to additional smart contract risk.

The architechtural design of the EigenPods system is inspired by various liquid staking protocols, particularly Rocket Pool 🚀.

## The EigenPodManager

The EigenPodManager facilitates the higher level functionality of EigenPods and their interactions with the rest of the EigenLayer smart contracts (the InvestmentManager and the InvestmentManager's owner). Stakers can call the EigenPodManager to create pods (whose addresses are determintically calculated via the Create2 OZ library) and stake on the Beacon Chain through them. The EigenPodManager also handles the cumulative paid penalties (explained later) of all EigenPods and allows the InvestmentManger's owner to redistribute them. 

## The EigenPod

The EigenPod is the contract that a staker must set their Etherum validators' withdrawal credentials to. EigenPods can be created by stakers through a call to the EigenPodManger. EigenPods are deployed using the beacon proxy pattern to have flexible global upgradability for future changes to the Ethereum specification. Stakers can stake for an Etherum validator when they create their EigenPod, through further calls to their EigenPod, and through parallel deposits to the Beacon Chain deposit contract.

### Beacon State Root Oracle

EigenPods extensively use a Beacon State Root Oracle that will bring beacon state roots into Ethereum for every [`SLOTS_PER_HISTORICAL_ROOT`](https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#time-parameters) slots (currently 8192 slots or ~27 hours) so that all intermediate state roots can be proven against the ones posted on execution layer.

### Proof of Correctly Pointed Withdrawal Credentials

After staking an Etherum validator with its withdrawal credentials pointed to their EigenPod, a staker must prove that the new validator exists and has its withdrawal credentials pointed to the EigenPod against a beacon state root. The EigenPod will verify the proof (along with checking for replays and other conditions) and finally credit the staker with `REQUIRED_BALANCE_WEI` shares of the virtual beacon chain ETH strategy in the InvestmentManager through a call to the EigenPod, if the validators balance is proven to be greater than `REQUIRED_BALANCE_WEI`. `REQUIRED_BALANCE_WEI` will be set initially to an amount of ether that a validator could get slashed down to only due to malice or negligence. The current back-of-the-hand calculations show that 31.4 ETH is the minimum balance an offline validator can have after a week of inactivity, so it sets a good indicator for `REQUIRED_BALANCE_WEI`. For reference, there are only about 50 validators below this balance on the Ethereum beacon chain as of 12/7/2022.

### Fraud Proofs for Overcommitted Balances

If a Ethereum validator restaked on an EigenPod has a balance that falls below `REQUIRED_BALANCE_WEI`, then they are over committed to EigenLayer, meaning they have less stake on the beacon chain than they have restaked Eigenlayer. Watchers can prove to EigenPods that the contract has a validator that is in such a state. If proof verification and other checks succeed, then `REQUIRED_BALANCE_WEI` will be immidiately decremented from the EigenPod owner's (the staker's) shares in the InvestmentManager. This causes a large negative externality to middlewares that the staker is securing since must endure get sudden downgrades in security whenever this happens. To punish stakers for this offense, `OVERCOMMITMENT_PENALTY_AMOUNT_GWEI` will be incremented to the penalties that the pod owner owes to EigenLayer (described later).

### Proofs of Full Withdrawals

Whenever an staker withdraws one of their validators from the beacon chain to provide liquidity, they have a few options. Stakers could keep the ETH in the EigenPod and continue staking on EigenLayer, in which case their ETH, when withdrawn to the EigenPod, will not earn any additional Ethereum staking yield, it will only earn their EigenLayer staking yield. Stakers could also queue withdrawals on EigenLayer for the virtual beacon chain ETH strategy which will be fullfilled once their staking obligations have ended and their EigenPod has enough balance to complete the withdrawal.

In this second case, in order to withdraw their balance from the EigenPod, stakers must provide a valid proof of their full withdrawal (differentiated from partil withdrawals through a simple comparison of the amount to a threshold) against a beacon state root. 

### Partial Withdrawal Claims

### Paying Penalties






## The Oracle

TBD
