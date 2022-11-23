
# EigenDA Contracts Flows

This outlines some of the details of contract-to-contract communications within EigenDA.

## Initiating a DataStore

![Initiating a DataStore in EigenDA](images/DL_init_datastore.png?raw=true "Initiating a DataStore in EigenDA")

1. The disperser calls `DataLayrServiceManager.initDataStore` (DLSM), providing relevant information about the DataStore.
2. The DLSM calls `DataLayrPaymentManager.payFee`, deducting from the disperser's pre-deposited payment balance. This assures the nodes in the network that payment has been provisioned for the DataStore (i.e. that they will be paid for storing the data).
3. Finally, after the DLSM updates its storage, it returns an index to the disperser, which specifies the location in the array `dataStoreHashesForDurationAtTimestamp[duration][block.timestamp]` at which the DataStore's hash was stored -- the index is useful in future operations that retrieve information related to the DataStore.
