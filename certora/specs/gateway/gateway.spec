using savETHOriginGateway as gateway
using savETHRegistry as savETHReg

methods {
    depositCount() returns uint256 envfree
    get_deposit_root() returns bytes32 envfree
    indexedHashes(uint256) returns bytes32 envfree
    indexedHashBlockNumber(bytes32) returns uint256 envfree
    isTransactionPushed(bytes32) returns bool envfree
    isNonceUsed(uint256) returns bool envfree
    MAX_DEPOSIT_COUNT() returns uint256 envfree
    branch(uint256) returns bytes32 envfree
    numberOfIndexedLeafs() returns uint256 envfree
    migratedKnotsIndexId() returns uint256 envfree              // Gateway savETH Index
}

// TODO - Write a ghost for the below that sums over any dETH in migrated index + adds sum of dETH in rest of universe and makes sure it does not exceed total supply
// knotDETHBalanceInIndex[KEY uint256 a][KEY bytes blsPubKey] returns uint256

//ghost sumAllDETHInMigratedKnotsIndexId(uint256) returns uint256 {
//    init_state axiom forall uint256 a. sumAllDETHInMigratedKnotsIndexId(a) == 0;
//}

//hook Sstore savETHReg.knotDETHBalanceInIndex[KEY uint256 a][KEY bytes b] uint256 balance
//(uint256 old_balance) STORAGE {
//  require balance <= max_uint128;
//  require old_balance <= max_uint128;
//  havoc sumAllDETHInMigratedKnotsIndexId assuming forall uint256 aa. (a==aa => sumAllDETHInMigratedKnotsIndexId@new(aa) == sumAllDETHInMigratedKnotsIndexId@old(aa) +
//      balance - old_balance) && (a != aa => sumAllDETHInMigratedKnotsIndexId@new(aa) == sumAllDETHInMigratedKnotsIndexId@old(aa));
//}

//invariant invariant_sumAllDETHInMigratedKnotsIndexId(env e)
//    sumAllDETHInMigratedKnotsIndexId(migratedKnotsIndexId()) == savETHReg.dETHInCirculation(e)

//rule sumOfDETHOnEthereumAndOptimismDoesNotExceedCirculatingSupplyOnMasterRegistry(env e) {
//}

// Ensure that the mintable balance cannot be accessed by the depositor
rule userIsNotAbleToMintOnEthereumAfterDeposit(
    env e,
    bytes blsPubKey,
    address house,
    uint256 destinationIndexId,
    bytes32 deposit_data_root
) {
    require blsPubKey.length == 32;
    uint256 associatedIndexIdForKnot = savETHReg.associatedIndexIdForKnot(e, blsPubKey);
    uint256 balance = savETHReg.knotDETHBalanceInIndex(e, associatedIndexIdForKnot, blsPubKey);

    deposit(e, house, blsPubKey, destinationIndexId, deposit_data_root);

    assert savETHReg.associatedIndexIdForKnot(e, blsPubKey) == migratedKnotsIndexId();
    assert savETHReg.knotDETHBalanceInIndex(e, migratedKnotsIndexId(), blsPubKey) == balance; // mintable cannot be minted any more by user
}

// indexedHashes.push(node); - this array only increases in size
rule treeIsAppendOnly(env e, calldataarg arg, method f) {
    uint256 numberOfIndexedLeafsBefore = numberOfIndexedLeafs();

    f(e, arg);

    uint256 numberOfIndexedLeafsAfter = numberOfIndexedLeafs();
    assert numberOfIndexedLeafsAfter != numberOfIndexedLeafsBefore => numberOfIndexedLeafsAfter == (numberOfIndexedLeafsBefore + 1)
        && (
            f.selector == deposit(address,bytes,uint256,bytes32).selector ||
            f.selector == push(bytes32,(address,bytes,uint256,uint256,uint256,uint256,uint256,address,uint256,address,uint256,uint256,bytes32),(uint248,uint8,bytes32,bytes32),bytes32[]).selector ||
            f.selector == pokeLatestBalance(address,bytes,bytes32).selector
        );
}

// `current_deposit_count * (current_deposit_count - 1) / 2 == sum(deposit_counts)` - ghost
// similar to if leaf 2 exists, then leaf 1 does etc.

// Ensure that deposit count cannot over flow and wipe out data in the tree
invariant depositCountCannotOverflow()
    depositCount() < MAX_DEPOSIT_COUNT()

// Insertion algorithm property - branch zero is always overwritten for odd deposit count
rule oddDepositCountsAlwaysOverwriteZeroBranch(
    env e,
    calldataarg arg,
    method f
) {
    uint256 countBefore = depositCount();
    bytes32 branchZeroBefore = branch(0);

    f(e, arg);

    uint256 countAfter = depositCount();
    bytes32 branchZeroAfter = branch(0);
    assert countAfter > countBefore && countAfter % 2 != 0 => branchZeroBefore != branchZeroAfter;
}

// Deposit count always increases by exactly one to avoid skipping the indexing of a leaf
rule depositCountOnlyIncreases(env e, calldataarg arg, method f)
{
    uint256 depositCountBefore = depositCount();

    f(e, arg);

    uint256 depositCountAfter = depositCount();
    assert depositCountAfter != depositCountBefore => depositCountAfter == depositCountBefore + 1
        && (
                f.selector == deposit(address,bytes,uint256,bytes32).selector ||
                f.selector == push(bytes32,(address,bytes,uint256,uint256,uint256,uint256,uint256,address,uint256,address,uint256,uint256,bytes32),(uint248,uint8,bytes32,bytes32),bytes32[]).selector ||
                f.selector == pokeLatestBalance(address,bytes,bytes32).selector
            );

}


// todo - Justin prove this and make stronger. add selectors in the assert and not filter as it is stronger this way
rule knownMethodsLikeDepositAlwaysProducesANewRoot(env e, method f)
filtered {
     f ->
         f.selector != initialize(address,uint256,uint256).selector &&
         f.selector != configureDestinationGateway(address,uint256).selector &&
         f.selector != authorizeCommittee(address,bool).selector &&
         !f.isView &&
         !f.isPure
    }
{
    bytes32 root = get_deposit_root();

    calldataarg arg;
    f(e, arg);

    assert get_deposit_root() != root;
}

// Deposit indexes the deposit leaf hash
rule depositIndexesLeafHashes(
     env e,
     address house,
     bytes blsPubKey,
     uint256 destinationIndexId,
     bytes32 depositDataRoot
 ) {
    require blsPubKey.length == 32;

    require isTransactionPushed(depositDataRoot) == false;

    deposit(e, house, blsPubKey, destinationIndexId, depositDataRoot);

    uint256 depositCount = depositCount();
    bytes32 fetchedLeaf = indexedHashes(depositCount - 1);

    assert fetchedLeaf == depositDataRoot;
    assert isTransactionPushed(fetchedLeaf) == true;
}

// After deposit, the block number is stored
rule depositStoresBlockNumber(
    env e,
    address house,
    bytes blsPubKey,
    uint256 destinationIndexId,
    bytes32 depositDataRoot
) {
    require blsPubKey.length == 32;

    require indexedHashBlockNumber(depositDataRoot) == 0;

    deposit(e, house, blsPubKey, destinationIndexId, depositDataRoot);

    assert indexedHashBlockNumber(depositDataRoot) != 0;
}

// Push records a UTXO nonce from the origin as used
rule pushRecordsNonceAsUsed(env e) {
    bytes32 _deposit_data_root;
    gateway.DepositMetadata depositMetadata;
    gateway.EIP712Signature signature;
    bytes32[] proof;

    require isNonceUsed(depositMetadata.depositIndex) == false;

    push(e, _deposit_data_root, depositMetadata, signature, proof);

    assert isNonceUsed(depositMetadata.depositIndex) == true;
}

// After push, the push leaf hash is indexed
rule pushIndexesLeafHashes(env e) {
    bytes32 _deposit_data_root;
    gateway.DepositMetadata depositMetadata;
    gateway.EIP712Signature signature;
    bytes32[] proof;

    require isTransactionPushed(_deposit_data_root) == false;

    push(e, _deposit_data_root, depositMetadata, signature, proof);

    assert isTransactionPushed(_deposit_data_root) == true;
}

// Associated block number for leaf is captured on push
rule pushStoresBlockNumber(env e) {
    bytes32 _deposit_data_root;
    gateway.DepositMetadata depositMetadata;
    gateway.EIP712Signature signature;
    bytes32[] proof;

    require indexedHashBlockNumber(_deposit_data_root) == 0;

    push(e, _deposit_data_root, depositMetadata, signature, proof);

    assert indexedHashBlockNumber(_deposit_data_root) != 0;
}