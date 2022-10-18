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
Each

## High-Level Goals (And How They Affect Design Decisions)
1. Anyone
    * all

###### tags: `docs`