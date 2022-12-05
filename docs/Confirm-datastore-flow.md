# Confirming a Datastore - The Flow

<!--add registering as on operator eventually-->

<A name="Initiate a DataStore"></A>
## Step 1: Initiate a DataStore

The first step to confirming a datastore is to initiate it.  `initDataStore` functions as a way of notifying EigenLayer that the disperser has asserted the blob of data into EigenDA, and is waiting to obtain the quorum signature of the EigenDA nodes on chain.  The fees associated with the datastore are also sent to the contract for escrow.  Another important step in this function involves posting the dataStore header on chain and verifying that the coding ratio specified in the header is adequate, i.e., it is greater than the minimum percentage of operators that must be honest signers.
```solidity
function initDataStore(
        address feePayer,
        address confirmer,
        uint8 duration,
        uint32 referenceBlockNumber,
        uint32 totalOperatorsIndex,
        bytes calldata header
    )
```


## Confirming a Datastore

```solidity
function confirmDataStore(
    bytes calldata data, 
    DataStoreSearchData memory searchData
) external onlyWhenNotPaused(PAUSED_CONFIRM_DATASTORE) 
```

The main function of the `confirmDataStore` function is to collect and verify the aggregate BLS signature of the quorum on the datastore.  The signature verification algorithm is as follows with these inputs:

```
<
    * bytes32 msgHash, the taskHash for which disperser is calling checkSignatures
    * uint48 index of the totalStake corresponding to the dataStoreId in the 'totalStakeHistory' array of the BLSRegistryWithBomb
    * uint32 blockNumber, the blockNumber at which the task was initated
    * uint32 taskNumberToConfirm
    * uint32 numberOfNonSigners,
    * {uint256[2] pubkeyG1, uint32 stakeIndex}[numberOfNonSigners] the G1 public key and the index to query of `pubkeyHashToStakeHistory` for each nonsigner,
    * uint32 apkIndex, the index in the `apkUpdates` array at which we want to load the aggregate public key
    * uint256[2] apkG1 (G1 aggregate public key, including nonSigners),
    * uint256[4] apkG2 (G2 aggregate public key, not including nonSigners),
    * uint256[2] sigma, the aggregate signature itself
    * 
>
```
The actual verification of the aggregate BLS signature on the datastore involves computing an elliptic curve pairing.  In order to arrive at this step, there are several things to be computed:

- The first step is to calculate the aggregate nonsigner public key, `aggNonSignerPubkeyG1` by adding all the nonsigner public keys in G1.  
- We then compute the aggregate signer public key, by computing `apkG1 - aggNonSignerPubkeyG1`.
- Now we can proceed to compute the pairing. The standard BLS pairing is as follows
$$x = 2$$



