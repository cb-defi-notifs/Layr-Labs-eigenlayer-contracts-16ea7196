---
title: EigenDA Contracts Technical Specification
description: Use `{%hackmd theme-dark %}` syntax to include this theme.
---

# EigenDA Contracts Technical Specification

## EigenDA Overview
See the introduction of the [DataLayr Technical Documentation](https://hackmd.io/VXNjJL3iS5W85UxB-mD3VQ) for an introduction. This doc also contains relevant technical details, in addition to outlining the different actors in the system.
EigenDA builts directly on top of [EigenLayer](https://hackmd.io/@layr/eigenlayer-tech-spec).

## Assumptions
We proceed from the same general assumptions as though outlined in the [EigenLayer technical specification](https://hackmd.io/@layr/eigenlayer-tech-spec). The most relevant assumption for EigenDA is the **Honest Watcher Assumption**.

## Creating a DataStore
### Introduction
The

### DataLayrServiceManager
The DataLayrServiceManager contract serves as the central contract for interacting with DataLayr.  It allows a disperser to assert chunks of data (called DataStores) into DataLayr and verify the asserted data with a quorum of signatures from DataLayr validator nodes.  This is a two step process:



1. First there is the `initDataStore` workflow which involves:
    - Notifying the settlement layer that the disperser has asserted the data into DataLayr and is waiting for a signature from the DataLayr operator quorum.
    - Place into escrow the service fees that the DataLayr operators will receive from the disperser.

2. Once the dataStore has been initialized, the disperser calls `confirmDataStore` which involves:
    * Notifying that signatures on the dataStore from quorum of DataLayr nodes have been obtained,
     * Check that the aggregate signature is valid,
     * Check whether quorum has been achieved or not.

### DataLayrPaymentManager
The DataLayrPaymentManager contract manages all DataLayr-related payments.  These payments are made per dataStore, usually over multiple dataStores. This contract inherits all of its functionalityfrom the `PaymentManager` contract. In addition to inherited methods from `PaymentManager`, the `DataLayrPaymentManager` contract specifies a `respondToPaymentChallengeFinal` method which specifies a DataLayr-specific final step to the payment challenge flow.

### DataLayrBombVerifier
The `DataLayrBombVerifier` is the core slashing module of DataLayr. Using Dankrad's Proofs of Custody, DataLayr is able to slash operators who are provably not storing their data.

If a challenger proves that a operator wasn't storing data at certain time, they prove the following 

1. The existence of a certain datastore referred to as the DETONATION datastore
2. The existence of a certain datastore referred to as the BOMB datastore, which the operator has certified to storing, that is chosen on-chain via the result of a function of the DETONATION datastore's header hash
3. The data that the operator was storing for the BOMB datastore, when hashed with the operator's ephemeral key and the DETONATION datastore's header hash, is below a certain threshold defined by the `DataLayrBombVerifier` contract
4. The operator certified the storing of DETONATION datastore

If these 4 points are proved, the operator is slashed. The operator should be checking the following above requirements against each new header hash it receives in order to not be slashed.

### BLSRegistry
The BLSRegistry contract inherits from the `RegistryBase` contract, and builds on top of it.

Designed primarily around a BLS signature scheme and 2-quorum model, it keeps track of all middleware operators and stores information relevant to each of them.

This contract acts as the point of entry and exit for middleware operators: before participating in middleware tasks, operators must register through calling the `registerOperator` function of the BLSRegistry; likewise, should an operator wish to cease providing services to the middleware, they can deregister by calling the `deregisterOperator` function of BLSRegistry. Note that in such a case, an operator must continue to serve their existing obligations; by deregistering an operator simply ceases to commit to serving *new* tasks (technically, this is following a brief delay as well -- the operator may also be required to serve new tasks created within approximately 8-10 minutes following their call to `deregisterOperator`).

Each active middleware operator is associated with a public key corresponding to a point on the quadratic extension of the alt_bn128 (i.e. Barreto-Naehrig, bn254, or bn256) curve aka the G2 of alt_bn128. New middleware operators provide a signature proving control over their public key to the BLSRegistry. In addition to storing all operators’ public keys, the BLSRegistry keeps track of the value of each operator’s stake, their position in an array of all operators, and the time until which they have committed to storing data.

Importantly, the BLSRegistry also stores an aggregate public key, against which the combined signatures of middleware operators can be checked. 
Additionally, BLSRegistry stores historical records of the aggregate public key, operator stakes, and operator array positions for all time. This historical data can all be referenced as needed, e.g. as part of the payment challenge process.

### BLSRegistryWithBomb
The BLSRegistryWithBomb contract inherits from the `BLSRegistry`, simply adding minimal functionality in order to support Data Availability Sampling (DAS) through interactions with an `EmphemeralKeyRegistry` contract.

### BLSSignatureChecker
This is the contract for checking that the aggregated signatures of all operators which is being asserted by the disperser is valid.  The contract's primary method is called `checkSignatures`.  It is called by disperser when it has aggregated all the signatures of the operators that are part of the quorum for a particular taskNumber and is asserting them into on-chain. It then checks that the claim for aggregated signatures are valid.  The thesis of this procedure entails:
* Computing the aggregated pubkey of all the operators that are not part of the quorum for this specific taskNumber (represented by aggNonSignerPubkey)
* Getting the aggregated pubkey of all registered nodes at the time of pre-commit by the disperser (represented by pk),
* Do subtraction of aggNonSignerPubkey from pk over Jacobian coordinate system to get aggregated pubkey of all operators that are part of quorum.
* Use this aggregated pubkey to verify the aggregated signature under BLS scheme.

### EphemeralKeyRegistry
The EphemeralKeyRegistry contract primarily serves to store revealed ephemeral keys for each operator, as a part of the "bomb" proof of custody scheme.  The proof of custody game works as follows: A given blob contains a bomb that is “detonated” if that blob is signed on by a DLN, resulting in slashing. Thus, the DLN must avoid signing that blob, forcing them to download and store the blob correctly to detect the bomb’s presence.

Whether or not a blob contains a bomb is determined by the ephemeral key. This ephemeral key is an arbitrary 32-byte value, unique to a given DLN, allowing them to detect the presence of a bomb. This happens as follows:
* Upon registering, the DLN generates a random ephemeral key (EK) and posts a commitment to it on chain. After a fixed period of time, the DLN reveals the EK and posts a commitment to a new EK.
* During this disclosure period, a challenger can check for the presence of a bomb in that DLN’s datastores. If a bomb is found and the DLN signed the block, the DLN is slashed!
* There are several additonal slashing conditions. The first is when a DLN fails to reveal the EK they committed to within a certain time frame, they are slashed. They are also slashed if their ephemeral key is revealed by a third party on chain before the disclosure period starts.

The main functionalities of this contract are:

(1) storing revealed ephemeral keys for each operator from past.
(2) checking if ephemeral keys revealed too early and then slashing if needed.
(3) recording when a previous ephemeral key is made inactive.

## High-Level Goals (And How They Affect Design Decisions)
1. Anyone
    * all

###### tags: `docs`