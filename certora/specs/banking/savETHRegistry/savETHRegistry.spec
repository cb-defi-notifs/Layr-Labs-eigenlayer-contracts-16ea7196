using savETH as savETHToken
using dETH as dETHToken
using StakeHouseAccessControls as access
using CertoraUtils as utils
using AccountManagerTest as accountManager

methods {
    knotdETHSharesMinted(bytes) returns (bool) envfree
    associatedIndexIdForKnot(bytes) returns (uint256) envfree
    dETHRewardsMintedForKnot(bytes) returns (uint256) envfree
    knotDETHBalanceInIndex(uint256,bytes) returns (uint256) envfree
    indexIdToOwner(uint256) returns (address) envfree
    approvedIndexSpender(uint256) returns (address) envfree
    indexPointer() returns uint256 envfree
    isKnotPartOfOpenIndex(bytes) returns (bool) envfree
    approvedKnotSpender(bytes,address) returns (address) envfree
    dETHInCirculation() returns (uint256) envfree
    dETHUnderManagementInOpenIndex() returns (uint256) envfree
    dETHMetadata() returns (uint128, uint128) envfree
    totalDETHMintedWithinHouse(address) returns (uint256) envfree
    totalDETHInIndices() returns (uint256) envfree
    dETHToSavETH(uint256) returns uint256 envfree

    isCoreModule(address) returns bool envfree => DISPATCHER(true)
    access.isCoreModule(address) returns bool envfree

    uint256ToUint128(uint256) returns (uint128) envfree => DISPATCHER(true)
    utils.uint256ToUint128(uint256) returns (uint128) envfree

    accountManager.blsPublicKeyToLifecycleStatus(bytes) returns (uint8) envfree;

    isSameBlsPubKey(bytes,bytes) returns (bool) envfree => DISPATCHER(true)
    utils.isSameBlsPubKey(bytes,bytes) returns (bool) envfree
}

function invokeParametric(env e, method f, address house, bytes blsPubKey) {
    require blsPubKey.length == 32;

    require dETHRewardsMintedForKnot(blsPubKey) <= 5000000000000000000000000; // if a knot earns more than 5m ETH then the beacon chain will have done amazing

    address owner;

    if (f.isFallback) {
        calldataarg arg;
        f@withrevert(e, arg);
    } else if (f.selector == transferKnotToAnotherIndex(address,bytes,address,uint256).selector) {
        uint256 index;
        require index > 0;
        transferKnotToAnotherIndex(e, house, blsPubKey, owner, index);
    } else if (f.selector == rageQuitKnot(address,bytes,address).selector) {
        rageQuitKnot(e, house, blsPubKey, owner);
    } else if (f.selector == addKnotToOpenIndexAndWithdraw(address,bytes,address,address).selector) {
        addKnotToOpenIndexAndWithdraw(e, house, blsPubKey, owner, owner);
    } else if (f.selector == addKnotToOpenIndex(address,bytes,address,address).selector) {
        addKnotToOpenIndex(e, house, blsPubKey, owner, owner);
    } else if (f.selector == mintSaveETHBatchAndDETHReserves(address,bytes,uint256).selector) {
        uint256 index;
        require index > 0;
        mintSaveETHBatchAndDETHReserves(e, house, blsPubKey, index);
    } else if (f.selector == depositAndIsolateKnotIntoIndex(address,bytes,address,uint256).selector) {
        uint256 index;
        require index > 0;
        depositAndIsolateKnotIntoIndex(e, house, blsPubKey, owner, index);
    } else if (f.selector == isolateKnotFromOpenIndex(address,bytes,address,uint256).selector) {
        uint256 index;
        require index > 0;
        isolateKnotFromOpenIndex(e, house, blsPubKey, owner, index);
    } else if (f.selector == approveSpendingOfKnotInIndex(address,bytes,address,address).selector) {
        approveSpendingOfKnotInIndex(e, house, blsPubKey, owner, owner);
    } else if (f.selector == mintDETHReserves(address,bytes,uint256).selector) {
        uint256 amount;
        require amount > 0;
        mintDETHReserves(e, house, blsPubKey, amount);
    } else {
        calldataarg arg;
        f(e, arg);
    }
}

//invariant invariant_dETHInIndicesIsAlwaysLessThanTotalDETHInIndices(uint256 index, bytes blsPubKeyA, uint256 indexB, bytes blsPubKeyB)
//    knotDETHBalanceInIndex(index, blsPubKeyA) + knotDETHBalanceInIndex(indexB, blsPubKeyB) <= totalDETHInIndices()
//    {
//        preserved {
//            require blsPubKeyA.length == 32;
//            require blsPubKeyB.length == 32;
//        }
//    }

/// ----------
/// Rules
/// ----------

// description: this rule is all about checking balances are correctly reducing.
//              this is not checking whether the KNOT is eligible for rage quit via redemption rate rules.
//              therefore the assumption is that given it is eligible, do balances correctly reduce
rule rageQuitKnotClearsBalances {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    address indexOwner;
    require indexOwner != 0;

    uint256 indexId = 1;
    require associatedIndexIdForKnot(blsPubKey) == indexId;

    uint256 knotDETHBalanceInIndexBefore = knotDETHBalanceInIndex(indexId, blsPubKey);
    require knotDETHBalanceInIndexBefore >= 24000000000000000000;

    address spender = approvedKnotSpender(blsPubKey,indexOwner);
    require spender != 0;

    uint256 dETHInCirculationBefore = dETHInCirculation();
    require dETHInCirculationBefore >= 24000000000000000000;
    require dETHInCirculationBefore >= knotDETHBalanceInIndexBefore;

    uint256 totalDETHMintedWithinHouseBefore = totalDETHMintedWithinHouse(stakeHouse);
    require totalDETHMintedWithinHouseBefore >= knotDETHBalanceInIndexBefore;

    rageQuitKnot(e, stakeHouse, blsPubKey, indexOwner);

    address spenderAfter = approvedKnotSpender(blsPubKey, indexOwner);
    assert spenderAfter == 0;

    uint256 knotDETHBalanceInIndexAfter = knotDETHBalanceInIndex(indexId, blsPubKey);
    assert knotDETHBalanceInIndexAfter == 0;

    uint256 associatedIndexAfter = associatedIndexIdForKnot(blsPubKey);
    assert associatedIndexAfter == 0;

    uint256 dETHInCirculationAfter = dETHInCirculation();
    assert dETHInCirculationAfter == (dETHInCirculationBefore - knotDETHBalanceInIndexBefore);

    uint256 totalDETHMintedWithinHouseAfter = totalDETHMintedWithinHouse(stakeHouse);
    assert totalDETHMintedWithinHouseAfter == (totalDETHMintedWithinHouseBefore - knotDETHBalanceInIndexBefore);
}

// description: new KNOT increases dETH minted in a house by 24
rule newKNOTIncreasesDETHMintedInHouseByTwentyFour {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 indexId;
    require indexId != 0;

    uint256 totalDETHMintedWithinHouseBefore = totalDETHMintedWithinHouse(stakeHouse);

    uint256 dETHInCirculationBefore = dETHInCirculation();
    require dETHInCirculationBefore == (max_uint128 - 24000000000000000000);

    mintSaveETHBatchAndDETHReserves(e, stakeHouse, blsPubKey, indexId);

    uint256 totalDETHMintedWithinHouseAfter = totalDETHMintedWithinHouse(stakeHouse);

    assert (totalDETHMintedWithinHouseAfter - totalDETHMintedWithinHouseBefore == 24000000000000000000, "dETH under management did not increase by 24e18");

    uint256 dETHInCirculationAfter = dETHInCirculation();
    assert dETHInCirculationAfter == (dETHInCirculationBefore + 24000000000000000000);
}

// description: set the issuance flag to true to ensure that issuance has been recorded and only done once
rule newKNOTSetsMintedFlagToTrue {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 indexId;
    require indexId != 0;

    bool dETHMintedBefore = knotdETHSharesMinted(blsPubKey);
    require dETHMintedBefore == false;

    mintSaveETHBatchAndDETHReserves(e, stakeHouse, blsPubKey, indexId);

    bool dETHMinted = knotdETHSharesMinted(blsPubKey);
    assert (dETHMinted == true, "dETH minted not set to true");
}

rule newKNOTDoesNotExpandERC20Supply {
    env e;
    address stakeHouse;
    bytes blsPubKey; require blsPubKey.length == 32;
    uint256 indexId;

    uint256 dETHSupplyBefore = dETHToken.totalSupply(e);
    uint256 savETHSupplyBefore = savETHToken.totalSupply(e);

    mintSaveETHBatchAndDETHReserves(e, stakeHouse, blsPubKey, indexId);

    uint256 dETHSupplyAfter = dETHToken.totalSupply(e);
    uint256 savETHSupplyAfter = savETHToken.totalSupply(e);

    assert dETHSupplyAfter == dETHSupplyBefore;
    assert savETHSupplyAfter == savETHSupplyBefore;
}

// description: when a user requests to add a KNOT to an index, it is added to the correct one
rule newKNOTIsAddedToTheCorrectIndex {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 indexId;
    require indexId != 0;

    uint256 associatedIndexIdBefore = associatedIndexIdForKnot(blsPubKey);
    require associatedIndexIdBefore == 0;

    mintSaveETHBatchAndDETHReserves(e, stakeHouse, blsPubKey, indexId);

    uint256 associatedIndexId = associatedIndexIdForKnot(blsPubKey);
    assert (associatedIndexId == indexId, "New KNOT is not associated with the correct index");
}

// description: Ensure that a new knot has 24 dETH balance when added to the specified index
rule newKNOTHasCorrectDETHBalInIndex {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 indexId;
    require indexId != 0;

    uint256 dETHBal = knotDETHBalanceInIndex(indexId, blsPubKey);
    require dETHBal == 0;

    mintSaveETHBatchAndDETHReserves(e, stakeHouse, blsPubKey, indexId);

    assert (knotDETHBalanceInIndex(indexId, blsPubKey) == 24000000000000000000, "New KNOT does not have correct bal in index");
}

// description: Ensure that no dETH and savETH is minted when adding a knot. a dETH balance of 24 is still recorded when adding to the index making this a 'mintable' supply. Tokens only minted on withdrawal like an ATM
rule invariant_newKnotDoesNotMintdETHorSavETHTokens {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 indexId;
    require indexId != 0;

    env e2;
    uint256 dETHTotalSupplyBefore = dETHToken.totalSupply(e2);
    uint256 savETHTotalSupplyBefore = savETHToken.totalSupply(e2);

    mintSaveETHBatchAndDETHReserves(e, stakeHouse, blsPubKey, indexId);

    uint256 dETHTotalSupplyAfter = dETHToken.totalSupply(e2);
    assert (dETHTotalSupplyAfter == dETHTotalSupplyBefore, "dETH supply changed");

    uint256 savETHTotalSupplyAfter = savETHToken.totalSupply(e2);
    assert (savETHTotalSupplyAfter == savETHTotalSupplyBefore, "savETH supply changed");
}

// description: When minting dETH rewards in the open index, the state is stored correctly i.e. more dETH in circulation, dETH rewards for the KNOT going up
rule openIndexRewardsCorrectlyRecorded {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 amount;
    require amount > 0 && amount < 10000000000000000000000000; // between > 0 and < 10m ether

    require isKnotPartOfOpenIndex(blsPubKey) == true;

    uint128 dETHUnderManagementBefore; uint128 dETHInCirculationBefore;
    dETHUnderManagementBefore, dETHInCirculationBefore = dETHMetadata();
    require dETHUnderManagementBefore <= 60000000000000000000000000;

    uint256 dETHRewardsMintedBefore = dETHRewardsMintedForKnot(blsPubKey);
    require dETHRewardsMintedBefore <= max_uint128;

    uint256 totalMintedInHouseBefore = totalDETHMintedWithinHouse(stakeHouse);
    require totalMintedInHouseBefore <= max_uint128;

    mintDETHReserves(e, stakeHouse, blsPubKey, amount);

    uint256 dETHRewardsMintedAfter = dETHRewardsMintedForKnot(blsPubKey);
    assert (dETHRewardsMintedAfter - dETHRewardsMintedBefore == amount, "minted did not correctly update");

    uint128 dETHUnderManagementAfter; uint128 dETHInCirculationAfter;
    dETHUnderManagementAfter, dETHInCirculationAfter = dETHMetadata();
    assert dETHInCirculationAfter - dETHInCirculationBefore == amount;

    assert (dETHUnderManagementAfter - dETHUnderManagementBefore == amount, "dUM did not increase correctly");

    uint256 totalMintedInHouseAfter = totalDETHMintedWithinHouse(stakeHouse);
    assert totalMintedInHouseAfter - totalMintedInHouseBefore == amount;
}

// description: regardless of whether knot is isolated, all minted dETH rewards are always recorded
rule dETHRewardsMintedCorrectlyRecorded {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    uint256 amount;
    require amount > 0 && amount <= 120000000000000000000000000; // between > 0 and <= 120m ether

    uint256 dETHRewardsMinted = dETHRewardsMintedForKnot(blsPubKey);
    require dETHRewardsMinted <= (max_uint128 - amount);

    mintDETHReserves(e, stakeHouse, blsPubKey, amount);

    uint256 dETHRewardsMintedAfter = dETHRewardsMintedForKnot(blsPubKey);

    assert (dETHRewardsMintedAfter - dETHRewardsMinted == amount, "Rewards minted for knot not equal to amount minted");
}

// description: index owner correctly changed when ownership transferred
rule transferIndexOwnershipCorrectlyUpdatesOwner {
    env e;

    uint256 indexId;
    require indexId != 0;

    address currentOwner = indexIdToOwner(indexId);
    require currentOwner != 0;

    address newOwner;
    require newOwner != 0;

    transferIndexOwnership(e, indexId, currentOwner, newOwner);

    address newAssignedOwner = indexIdToOwner(indexId);

    assert (newAssignedOwner == newOwner, "New assign owner not as expected");
}

// description: ensure dETH balance of KNOT in one index is correctly transferred to another index when owner or spender does this action
rule transferKnotToAnotherIndexTransfersFullDETHBalanceToNewIndex {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    address indexOwner;
    require indexOwner != 0;

    uint256 currentIndexId = associatedIndexIdForKnot(blsPubKey);
    require currentIndexId != 0;

    uint256 knotDETHBalanceInIndexBefore = knotDETHBalanceInIndex(currentIndexId, blsPubKey);
    require knotDETHBalanceInIndexBefore != 0;

    address currentIndexOwner = indexIdToOwner(currentIndexId);
    require currentIndexOwner == indexOwner;

    uint256 newIndexId;
    require newIndexId != 0;
    require currentIndexId != newIndexId;

    address newIndexOwner = indexIdToOwner(newIndexId);
    require newIndexOwner == indexOwner;

    transferKnotToAnotherIndex(e, stakeHouse, blsPubKey, currentIndexOwner, newIndexId);

    uint256 knotDETHBalanceInOldIndex = knotDETHBalanceInIndex(currentIndexId, blsPubKey);
    assert (knotDETHBalanceInOldIndex == 0, "bal in old index should be zero");

    uint256 newAssociatedIndexId = associatedIndexIdForKnot(blsPubKey);
    assert (newAssociatedIndexId == newIndexId, "Not associated with correct index");

    uint256 knotDETHBalanceInNewIndex = knotDETHBalanceInIndex(newIndexId, blsPubKey);
    assert (knotDETHBalanceInNewIndex == knotDETHBalanceInIndexBefore, "bal in new index should be what was in old index");

    // transfer back to the original index clears balances correctly
    transferKnotToAnotherIndex(e, stakeHouse, blsPubKey, currentIndexOwner, currentIndexId);

    uint256 knotDETHBalanceInNewIndexAfter = knotDETHBalanceInIndex(newIndexId, blsPubKey);
    assert (knotDETHBalanceInNewIndexAfter == 0, "bal in new index should be zero now");
}

// description: for the case that there is a savETH supply, withdrawing dETH burns savETH and mints dETH
rule withdrawReducesSavETHSupplyAndIncreasesDETHSupply {
    env e;

    address owner;
    require owner != 0;

    env e2;
    uint256 totalSavETHSupplyBefore = savETHToken.totalSupply(e2);
    require totalSavETHSupplyBefore > 0;

    uint128 amount;
    require amount > 0 && amount <= savETHToken.totalSupply(e2);

    uint256 dETHTotalSupplyBefore = dETHToken.totalSupply(e2);
    require dETHTotalSupplyBefore <= max_uint128;

    uint256 dUM = dETHUnderManagementInOpenIndex();
    uint256 dETHToMint;
    if (dUM == totalSavETHSupplyBefore) {
        dETHToMint = amount;
    } else {
        dETHToMint = (amount * dUM) / totalSavETHSupplyBefore;
    }

    withdraw(e, owner, owner, amount);

    uint256 totalSavETHSupplyAfter = savETHToken.totalSupply(e2);
    assert (totalSavETHSupplyBefore - totalSavETHSupplyAfter == amount, "Total savETH did not decrease by the right amount");

    uint256 dETHTotalSupplyAfter = dETHToken.totalSupply(e2);
    assert(dETHTotalSupplyAfter - dETHTotalSupplyBefore == dETHToMint, "dETH supply did not increase");
}

// description: when creating index, ensure pointer which assignes an index ID is correctly incremented assuming no overflow
rule createIndexIncrementsTheIndexPointerByOne {
    env e;

    address owner;
    require owner != 0;

    uint256 pointerBefore = indexPointer();
    require pointerBefore < max_uint256;

    createIndex(e, owner);

    uint256 pointerAfter = indexPointer();

    assert (pointerAfter - pointerBefore == 1, "Pointer did not increment by one");
}

// description: ensure approvals are cleared when index ownership is transferred
rule transferIndexOwnershipClearsApproval {
    env e;

    uint256 indexId;
    require indexId != 0;

    address approvedSpender = approvedIndexSpender(indexId);
    require approvedSpender != 0;

    address currentOwnerOrSpender;
    require currentOwnerOrSpender != 0;

    address newOwner;
    require newOwner != 0;

    transferIndexOwnership(e, indexId, currentOwnerOrSpender, newOwner);

    address approvedSpenderAfter = approvedIndexSpender(indexId);
    assert (approvedSpenderAfter == 0, "Approval not cleared");
}

// description: ensure approvals are cleared when transferring a KNOT to another index
rule transferKnotToAnotherIndexClearsApproval {
    env e;

    address stakeHouse;

    bytes blsPubKey; require blsPubKey.length == 32;

    address indexOwner; require indexOwner != 0;

    uint256 indexId;
    require indexId != 0;
    require indexIdToOwner(indexId) == indexOwner;

    require associatedIndexIdForKnot(blsPubKey) == indexId;

    address approvedSpenderBefore = approvedKnotSpender(blsPubKey, indexOwner);
    require approvedSpenderBefore != 0 && approvedSpenderBefore != indexOwner;

    transferKnotToAnotherIndex(e, stakeHouse, blsPubKey, approvedSpenderBefore, indexId);

    address approvedSpenderAfter = approvedKnotSpender(blsPubKey, indexOwner);
    assert (approvedSpenderAfter == 0, "Approval not cleared");
}

// description: knots within an index that are approved for transfer don't retain approval when index ownership is transferred (this is based on current owner)
// TODO - check that this is working as expected
rule transferIndexOwnershipInvalidatesKnotApproval {
    env e;

    address stakeHouse;

    bytes blsPubKey; require blsPubKey.length == 32;

    address indexOwner; require indexOwner != 0;

    uint256 indexId;
    require indexId != 0;
    require indexIdToOwner(indexId) == indexOwner;

    require associatedIndexIdForKnot(blsPubKey) == indexId;

    address approvedSpenderBefore = approvedKnotSpender(blsPubKey, indexOwner);
    require approvedSpenderBefore != 0 && approvedSpenderBefore != indexOwner;

    address newOwner;
    require newOwner != 0 && newOwner != indexOwner;

    require approvedKnotSpender(blsPubKey, newOwner) == 0;

    transferIndexOwnership(e, indexId, indexOwner, newOwner);

    assert indexIdToOwner(indexId) == newOwner;

    assert (approvedKnotSpender(blsPubKey, newOwner) == 0, "Approval not cleared");
    assert (approvedKnotSpender(blsPubKey, indexOwner) == approvedSpenderBefore, "Approval cleared");
}

// description: only core modules are allowed to call state changing methods in savETH registry
rule invariant_nonCoreModuleShouldNotBeAbleToCallAnyStateChangeMethod(method f)
filtered {
     f ->
         f.selector != init(address,address,address).selector &&
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address,bytes).selector &&
         !f.isView &&
         !f.isPure
     }
{
    env e;

    require e.msg.sender != 0;

    bool isCore = access.isCoreModule(e.msg.sender);
    require isCore == false;

    calldataarg arg;
    f@withrevert(e, arg);

    assert lastReverted;
}

// description: inverse of withdrawReducesSavETHSupplyAndIncreasesDETHSupply where depositing dETH burns it and mints savETH when dETH added to an index
 rule depositDecreasesDETHSupplyAndIncreasesSavETHSupply {
     env e;

     address owner;
     require owner != 0;

     env e2;
     uint256 dETHTotalSupplyBefore = dETHToken.totalSupply(e2);
     require dETHTotalSupplyBefore > 0;

     uint128 amount;
     require amount > 0 && amount <= dETHTotalSupplyBefore;

     uint256 savETHSupplyBefore = savETHToken.totalSupply(e2);
     require savETHSupplyBefore <= max_uint128;

     uint256 dETHUnderManagement = dETHUnderManagementInOpenIndex();
     uint256 savETHToMint;

     if (dETHUnderManagement == 0) {
        savETHToMint = amount;
     } else {
        savETHToMint = ((amount * savETHSupplyBefore) / dETHUnderManagementInOpenIndex());
     }

     deposit(e, owner, owner, amount);

     uint256 dETHTotalSupplyAfter = dETHToken.totalSupply(e2);
     assert (dETHTotalSupplyBefore - dETHTotalSupplyAfter == amount, "dETH supply did not drop by the amount deposited");

     uint256 savETHSupplyAfter = savETHToken.totalSupply(e2);
     assert (
        savETHSupplyAfter - savETHSupplyBefore == savETHToMint,
        "savETH supply did not increase"
    );
 }

// description: when depositing straight into an index, dETH supply decreases and correct amount assigned to index
 rule depositAndIsolateKnotIntoIndexDecreasesDETHTokenSupplyAndAddsTheBalanceIntoAnIndex {
     env e;

     address house;
     require house != 0;

     bytes blsPubKey;
     require blsPubKey.length == 32;

     address owner;
     require owner != 0;

     env e2;
     uint256 dETHTotalSupplyBefore = dETHToken.totalSupply(e2);

     uint256 rewardsMinted = dETHRewardsMintedForKnot(blsPubKey);
     require rewardsMinted <= max_uint32;

     uint256 dETHRequiredForIsolation;
     require dETHRequiredForIsolation == 24000000000000000000;

     require dETHTotalSupplyBefore >= (dETHRequiredForIsolation + rewardsMinted) && dETHTotalSupplyBefore <= max_uint128;

     uint256 savETHSupplyBefore = savETHToken.totalSupply(e2);
     require savETHSupplyBefore <= max_uint128;

     uint256 dETHUnderManagement = dETHUnderManagementInOpenIndex();

     uint256 indexId;
     require indexId != 0;
     require knotDETHBalanceInIndex(indexId, blsPubKey) == 0;

     depositAndIsolateKnotIntoIndex(e, house, blsPubKey, owner, indexId);

     assert knotDETHBalanceInIndex(indexId, blsPubKey) == (dETHRequiredForIsolation + rewardsMinted);

     uint256 dETHTotalSupplyAfter = dETHToken.totalSupply(e2);
     assert (dETHTotalSupplyBefore - dETHTotalSupplyAfter == (dETHRequiredForIsolation + rewardsMinted), "dETH supply did not drop by the amount deposited");

     uint256 savETHSupplyAfter = savETHToken.totalSupply(e2);
     assert (savETHSupplyAfter == savETHSupplyBefore, "savETH supply did not stay static");
 }

// description: Going straight from index to dETH minted in wallet correctly adjusts the accounting in the savETH registry and only mints dETH
// todo - go over this logic again and inject bugs
 rule addKnotToOpenIndexAndWithdrawClearsTheIndexAndIncreasesDETHSupplyOnly {
    env e;

    address house; require house != 0;
    bytes blsPubKey; require blsPubKey.length == 32;
    address owner; require owner != 0;

    uint256 currentIndexId; require currentIndexId != 0;

    uint256 associatedIndexId = associatedIndexIdForKnot(blsPubKey);
    require associatedIndexId == currentIndexId;

    uint256 balInIndexBefore = knotDETHBalanceInIndex(associatedIndexId, blsPubKey);
    require balInIndexBefore >= 24000000000000000000 && balInIndexBefore <= 960000000000000000000;

    env e2;
    uint256 dETHTotalSupplyBefore = dETHToken.totalSupply(e2);
    require dETHTotalSupplyBefore <= max_uint128;

    uint256 ownerDETHBalBefore = dETHToken.balanceOf(e2, owner);
    require ownerDETHBalBefore == 0;

    uint256 savETHSupplyBefore = savETHToken.totalSupply(e2);

    addKnotToOpenIndexAndWithdraw(e, house, blsPubKey, owner, owner);

    env e3;
    assert dETHToken.balanceOf(e3, owner) == balInIndexBefore;
    assert dETHToken.totalSupply(e3) == (balInIndexBefore + dETHTotalSupplyBefore);
    assert knotDETHBalanceInIndex(associatedIndexId, blsPubKey) == 0;
 }

// description: savETH supply should reduce as dETH is added to a knot within an index
rule isolatingKnotFromOpenIndexReducesSavETHSupplyAndAddsDETHToIndex {
  env e;

  address stakeHouse; require stakeHouse != 0;
  bytes blsPubKey; require blsPubKey.length == 32;
  address savETHOwner; require savETHOwner != 0;
  uint256 targetIndexId; require targetIndexId != 0;

  uint256 balInIndexBefore = knotDETHBalanceInIndex(targetIndexId, blsPubKey);
  require balInIndexBefore == 0;

  env e2;
  uint256 savETHSupplyBefore = savETHToken.totalSupply(e2);
  require savETHSupplyBefore >= 24000000000000000000 && savETHSupplyBefore <= max_uint64;

  // dETH can be bigger than savETH supply (if there are rewards)
  uint256 dETHUnderManagementBefore = dETHUnderManagementInOpenIndex();
  require dETHUnderManagementBefore >= savETHSupplyBefore && dETHUnderManagementBefore <= max_uint128;

  // minted rewards ignored now
  uint256 dETHRewardsMinted = dETHRewardsMintedForKnot(blsPubKey);
  require dETHRewardsMinted <= max_uint64;

  uint256 dETHRequiredForIsolation = 24000000000000000000 + dETHRewardsMinted;

  uint256 expectedSavETHBalFromOwner = (dETHRequiredForIsolation * savETHSupplyBefore) / dETHUnderManagementBefore;

  env e3;
  uint256 savETHOwnerBal = savETHToken.balanceOf(e3, savETHOwner);
  require savETHOwnerBal >= expectedSavETHBalFromOwner;

  isolateKnotFromOpenIndex(e, stakeHouse, blsPubKey, savETHOwner, targetIndexId);

  uint256 dETHUnderManagementAfter = dETHUnderManagementInOpenIndex();

  env e4;
  uint256 savTotalAfter = savETHToken.totalSupply(e4);
  assert savETHSupplyBefore - savTotalAfter == expectedSavETHBalFromOwner;

  assert (dETHUnderManagementBefore - dETHUnderManagementAfter) == dETHRequiredForIsolation;
  assert knotDETHBalanceInIndex(targetIndexId, blsPubKey) == dETHRequiredForIsolation;
}

// description: when moving dETH from an index into the open index, this should mint savETH
rule addingKnotToOpenIndexMintsSavETH {
    env e;

    address stakeHouse; require stakeHouse != 0;
    bytes blsPubKey; require blsPubKey.length == 64;
    address indexOwner; require indexOwner != 0;
    uint256 indexIdForKnot = associatedIndexIdForKnot(blsPubKey); require indexIdForKnot != 0;

    uint256 dETHToSend = knotDETHBalanceInIndex(indexIdForKnot, blsPubKey);
    require dETHToSend >= 24000000000000000000 && dETHToSend <= max_uint128;

    uint256 dETHUnderManagementBefore = dETHUnderManagementInOpenIndex();
    require dETHUnderManagementBefore <= max_uint128;

    env e2;
    uint256 savETHTotalSupplyBefore = savETHToken.totalSupply(e2);
    require savETHTotalSupplyBefore <= max_uint128;

    uint256 savETHToMint;
    if (dETHUnderManagementBefore == 0) {
        require savETHTotalSupplyBefore == 0;
        savETHToMint = dETHToSend;
    } else {
        require savETHTotalSupplyBefore >= 24000000000000000000;
        savETHToMint = (dETHToSend * savETHTotalSupplyBefore) / dETHUnderManagementBefore;
    }

    addKnotToOpenIndex(e, stakeHouse, blsPubKey, indexOwner, indexOwner);

    env e3;
    uint256 savETHTotalSupplyAfter = savETHToken.totalSupply(e3);
    assert (savETHTotalSupplyAfter - savETHTotalSupplyBefore == savETHToMint, "savETH supply did not increase by the correct amount");

    uint256 dETHUnderManagementAfter = dETHUnderManagementInOpenIndex();
    assert (dETHUnderManagementAfter - dETHUnderManagementBefore == dETHToSend, "dETH in open index did not increase by the correct amount");
}

/// ----------
/// Invariants
/// ----------


definition knotBalanceInIndexCalculatedCorrectly(uint256 indexId,bytes blsPubKey) returns bool =
    knotDETHBalanceInIndex(indexId,blsPubKey) > 0 => knotDETHBalanceInIndex(indexId,blsPubKey) == (24000000000000000000 + dETHRewardsMintedForKnot(blsPubKey));

// description: Ensure that if there is an index balance for a knot, that the balance is at least 24 and if there have been inflation rewards that is also factored. Bal == 24 + inflation rewards
rule invariant_dETHBalanceInIndexIsAlwaysTwentyFourPlusRewards(uint256 indexId, bytes blsPubKey, address house, address user, env e, method f)
filtered{  f ->
                          f.selector != upgradeToAndCall(address,bytes).selector &&
                          f.selector != upgradeTo(address).selector &&
                          !f.isFallback
            }
{
    require indexId != 0; // cannot be in open index
    require blsPubKey.length == 32;

    require knotdETHSharesMinted(blsPubKey) == false => dETHRewardsMintedForKnot(blsPubKey) == 0;
    require knotDETHBalanceInIndex(indexId,blsPubKey) > 0 => knotDETHBalanceInIndex(indexId,blsPubKey) == 24000000000000000000 + dETHRewardsMintedForKnot(blsPubKey);

    if (f.selector == mintSaveETHBatchAndDETHReserves(address,bytes,uint256).selector) {
        mintSaveETHBatchAndDETHReserves(e,house,blsPubKey,indexId);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else if (f.selector == transferKnotToAnotherIndex(address,bytes,address,uint256).selector) {
        uint256 newIndex; require newIndex != 0 && newIndex != indexId;
        require associatedIndexIdForKnot(blsPubKey) == indexId;
        transferKnotToAnotherIndex(e,house,blsPubKey,user,newIndex);
        assert knotDETHBalanceInIndex(indexId,blsPubKey) == 0;
        assert knotDETHBalanceInIndex(newIndex,blsPubKey) == (24000000000000000000 + dETHRewardsMintedForKnot(blsPubKey));
    } else if (f.selector == mintDETHReserves(address,bytes,uint256).selector) {
        require associatedIndexIdForKnot(blsPubKey) == indexId;
        uint256 amount;

        if (knotDETHBalanceInIndex(indexId,blsPubKey) == 0) {
            require knotDETHBalanceInIndex(indexId,blsPubKey) == 24000000000000000000 + dETHRewardsMintedForKnot(blsPubKey);
        }

        mintDETHReserves(e,house,blsPubKey,amount);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else if (f.selector == isolateKnotFromOpenIndex(address,bytes,address,uint256).selector) {
        isolateKnotFromOpenIndex(e,house,blsPubKey,user,indexId);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else if (f.selector == depositAndIsolateKnotIntoIndex(address,bytes,address,uint256).selector) {
        depositAndIsolateKnotIntoIndex(e,house,blsPubKey,user,indexId);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else if (f.selector == addKnotToOpenIndexAndWithdraw(address,bytes,address,address).selector) {
        require associatedIndexIdForKnot(blsPubKey) == indexId;
        require indexIdToOwner(indexId) == user;
        addKnotToOpenIndexAndWithdraw(e,house,blsPubKey,user,user);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else if (f.selector == rageQuitKnot(address,bytes,address).selector) {
        require associatedIndexIdForKnot(blsPubKey) == indexId;
        require indexIdToOwner(indexId) == user;
        rageQuitKnot(e,house,blsPubKey,user);
        assert knotDETHBalanceInIndex(indexId,blsPubKey) == 0;
        assert dETHRewardsMintedForKnot(blsPubKey) == 0;
    } else if (f.selector == addKnotToOpenIndex(address,bytes,address,address).selector) {
       require associatedIndexIdForKnot(blsPubKey) == indexId;
       require indexIdToOwner(indexId) == user;
       addKnotToOpenIndex(e,house,blsPubKey,user,user);
       assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else if (f.selector == approveSpendingOfKnotInIndex(address,bytes,address,address).selector) {
        require associatedIndexIdForKnot(blsPubKey) == indexId;
        address indexOwner;
        address spender;
        approveSpendingOfKnotInIndex(e,house,blsPubKey,indexOwner,spender);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
    } else {
        calldataarg arg;
        f(e, arg);
        assert knotBalanceInIndexCalculatedCorrectly(indexId, blsPubKey);
     }
}

// todo - specific rules for adding a knot to open index and isolating
 rule dETHUnderManagementAndTotalSavETHSupplyAreEitherZeroOrNonZeroAtTheSameTime(method f)
 filtered {
     f ->
         f.selector != init(address,address,address).selector &&
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address,bytes).selector
     }
 {
     env e;

     uint128 dETHUnderManagement; uint128 dETHInCirculation;
     dETHUnderManagement, dETHInCirculation = dETHMetadata();

     env e2;
     uint256 savETHMintedTotalSupply = savETHToken.totalSupply(e2);
     uint256 totalSavETHSupply = savETHMintedTotalSupply;

     require (dETHUnderManagement == 0 <=> totalSavETHSupply == 0);

     if (
        f.selector == addKnotToOpenIndex(address,bytes,address,address).selector
        ) {
         require dETHUnderManagement > 0;
         require totalSavETHSupply > 0;
     }

     address house; bytes blsPubKey;
     invokeParametric(e, f, house, blsPubKey);

     uint128 dETHUnderManagementAfter; uint128 dETHInCirculationAfter;
     dETHUnderManagementAfter, dETHInCirculationAfter = dETHMetadata();

     uint256 savETHMintedTotalSupplyAfter = savETHToken.totalSupply(e2);
     uint256 totalSavETHSupplyAfter = savETHMintedTotalSupplyAfter;

     assert (dETHUnderManagementAfter == 0 <=> totalSavETHSupplyAfter == 0);
 }

// description: expose which fns adjust mintable supply of savETH
rule invariant_dETHInCirculationStaysConstant(method f)
filtered { f ->
            f.selector != mintDETHReserves(address,bytes,uint256).selector &&
            f.selector != mintSaveETHBatchAndDETHReserves(address,bytes,uint256).selector &&
            f.selector != rageQuitKnot(address,bytes,address).selector &&
            f.selector != upgradeTo(address).selector &&
            f.selector != upgradeToAndCall(address,bytes).selector
        }
{
    uint256 dETHInCirculationBefore = dETHInCirculation();
    require dETHInCirculationBefore <= max_uint128;

    env e;
    address house; bytes blsPubKey;
    invokeParametric(e, f, house, blsPubKey);

    assert dETHInCirculation() == dETHInCirculationBefore;
}

// description: check which functions keep total dETH under management constant
// only fns that should fail for this invariant this are: deposit, withdraw, mintDETHReserves, mintSaveETHBatchAndDETHReserves, rageQuitKnot
rule invariant_totaldETHUnderManagementStaysSame(method f)
filtered { f ->
            f.selector != deposit(address,address,uint128).selector &&
            f.selector != withdraw(address,address,uint128).selector &&
            f.selector != addKnotToOpenIndex(address,bytes,address,address).selector &&
            f.selector != isolateKnotFromOpenIndex(address,bytes,address,uint256).selector &&
            f.selector != mintDETHReserves(address,bytes,uint256).selector &&
            f.selector != init(address,address,address).selector &&
            f.selector != upgradeTo(address).selector &&
            f.selector != upgradeToAndCall(address,bytes).selector
        }
{
    uint256 dETHUnderManagementBefore = dETHUnderManagementInOpenIndex();

    env e;
    address house; bytes blsPubKey;
    invokeParametric(e, f, house, blsPubKey);

    assert dETHUnderManagementInOpenIndex() == dETHUnderManagementBefore;
}

// description: check which functions keep total savETH supply constant
// total savETH supply = minted supply
rule invariant_totalSavETHSupplyStaysSame(method f)
filtered { f ->
            f.selector != deposit(address,address,uint128).selector &&
            f.selector != withdraw(address,address,uint128).selector &&
            f.selector != addKnotToOpenIndex(address,bytes,address,address).selector &&
            f.selector != isolateKnotFromOpenIndex(address,bytes,address,uint256).selector &&
            f.selector != init(address,address,address).selector
        }
{
    env e;

    env e2;
    uint256 savETHTotalSupplyBefore = savETHToken.totalSupply(e2);
    require savETHTotalSupplyBefore < max_uint128;

    calldataarg arg;
    f(e, arg);

    uint256 savETHTotalSupplyAfter = savETHToken.totalSupply(e2);

    assert savETHTotalSupplyAfter == savETHTotalSupplyBefore;
}

// description: only 1 function should increase the index pointer (total number of indices) - createIndex(address)
rule invariant_indexPointerIsStaticOutsideOfCreatingAnIndex(method f)
filtered { f ->
        f.selector != createIndex(address).selector &&
        f.selector != upgradeTo(address).selector &&
        f.selector != upgradeToAndCall(address,bytes).selector
    }
{
    uint256 pointerBefore = indexPointer();

    env e;
    address house; bytes blsPubKey;
    invokeParametric(e, f, house, blsPubKey);

    uint256 pointerAfter = indexPointer();
    assert (pointerAfter == pointerBefore, "Pointer changed");
}

/// description: Only known functions should increase the dETH in circulation
rule onlyAddingAKnotOrMintingInflationRewardsCanIncreaseCirculatingSupplyOfdETH(env e, method f)
filtered { f ->
        f.selector != upgradeTo(address).selector &&
        f.selector != upgradeToAndCall(address,bytes).selector
    }
{
    uint256 dETHInCirculationBefore = dETHInCirculation();

    address house; bytes blsPubKey;
    invokeParametric(e, f, house, blsPubKey);

    uint256 dETHInCirculationAfter = dETHInCirculation();

    assert dETHInCirculationAfter > dETHInCirculationBefore =>
        f.selector == mintDETHReserves(address,bytes,uint256).selector ||
        f.selector == mintSaveETHBatchAndDETHReserves(address,bytes,uint256).selector;
}

/// description: Only known functions should increase the dETH minted within a house
rule onlyAddingAKnotOrMintingInflationRewardsCanIncreaseTotalDETHMintedInHouse(env e, method f)
filtered { f ->
        f.selector != upgradeTo(address).selector &&
        f.selector != upgradeToAndCall(address,bytes).selector
    }
{
    address house; bytes blsPubKey;
    uint256 totalDETHMintedWithinHouseBefore = totalDETHMintedWithinHouse(house);

    invokeParametric(e, f, house, blsPubKey);

    uint256 totalDETHMintedWithinHouseAfter = totalDETHMintedWithinHouse(house);

    assert totalDETHMintedWithinHouseAfter > totalDETHMintedWithinHouseBefore =>
        f.selector == mintDETHReserves(address,bytes,uint256).selector ||
        f.selector == mintSaveETHBatchAndDETHReserves(address,bytes,uint256).selector;
}

/// description: Helper function to isolate the blsPublicKey parameter
function callFuncWithParams(method f, env e, bytes blsPublicKey) {

    address stakehouse;
    uint256 amount;
    address indexOwner;
    address recipient;
    uint256 newIndexId;
    uint256 indexId;

    if (f.selector == mintDETHReserves(address,bytes,uint256).selector) {
        mintDETHReserves(e, stakehouse, blsPublicKey, amount);
    }

    else if (f.selector == addKnotToOpenIndexAndWithdraw(address,bytes,address,address).selector) {
        addKnotToOpenIndexAndWithdraw(e, stakehouse, blsPublicKey, indexOwner, recipient);
    }

    else if (f.selector == transferKnotToAnotherIndex(address,bytes,address,uint256).selector) {
        transferKnotToAnotherIndex(e, stakehouse, blsPublicKey, indexOwner, newIndexId);
    }

    else if (f.selector == addKnotToOpenIndex(address,bytes,address,address).selector) {
        addKnotToOpenIndex(e, stakehouse, blsPublicKey, indexOwner, recipient);
    }

    else if (f.selector == mintSaveETHBatchAndDETHReserves(address,bytes,uint256).selector) {
        mintSaveETHBatchAndDETHReserves(e, stakehouse, blsPublicKey, indexId);
    }

    else if (f.selector == depositAndIsolateKnotIntoIndex(address,bytes,address,uint256).selector) {
        depositAndIsolateKnotIntoIndex(e, stakehouse, blsPublicKey, indexOwner, indexId);
    }

    else if (f.selector == isolateKnotFromOpenIndex(address,bytes,address,uint256).selector) {
        isolateKnotFromOpenIndex(e, stakehouse, blsPublicKey, indexOwner, indexId);
    }

    else if (f.selector == rageQuitKnot(address,bytes,address).selector) {
        rageQuitKnot(e, stakehouse, blsPublicKey, indexOwner);
    }

    else if (f.selector == approveSpendingOfKnotInIndex(address,bytes,address,address).selector) {
        approveSpendingOfKnotInIndex(e,stakehouse,blsPublicKey,indexOwner,recipient);
    }

    else {
        calldataarg args;
        f(e,args);
    }
}

rule indexPointerOnlyIncreases(env e, method f)
filtered {
     f ->
         f.selector != init(address,address,address).selector &&
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address,bytes).selector &&
         f.selector != rageQuitKnot(address,bytes,address).selector &&
         !f.isView &&
         !f.isPure
     }
{
    calldataarg args;

    uint256 pointerBefore = indexPointer();
    bytes blsPublicKey;

    require blsPublicKey.length <= 7;

    require pointerBefore < max_uint256 - 1;

    callFuncWithParams(f, e, blsPublicKey);

    uint256 pointerAfter = indexPointer();

    assert pointerBefore <= pointerAfter;
}

// description: A knot can only have an isolated mintable balance of at least 24 dETH if it is associated with an index but if in the open index then balance must be zero
// description: In other words: A knot has a zero personal index balance when in the open index
rule knotCannotHaveNonZeroDETHBalanceWhenAssociatedWithAnIndex(
    env e,
    method f,
    calldataarg args,
    bytes blsPubKey
)
filtered {
        f ->
              f.selector != upgradeToAndCall(address,bytes).selector &&
              f.selector != upgradeTo(address).selector
    }
{

    require blsPubKey.length == 32;

    require associatedIndexIdForKnot(blsPubKey) > 0 => knotDETHBalanceInIndex(associatedIndexIdForKnot(blsPubKey), blsPubKey) >= 24000000000000000000;

    callFuncWithParams(f, e, blsPubKey);

    assert associatedIndexIdForKnot(blsPubKey) > 0 => knotDETHBalanceInIndex(associatedIndexIdForKnot(blsPubKey), blsPubKey) >= 24000000000000000000;
}

rule dETHMintedForKnotOnlyIncreasing(env e, method f)
filtered {
     f ->
         f.selector != init(address,address,address).selector &&
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address,bytes).selector &&
         f.selector != rageQuitKnot(address,bytes,address).selector &&
         !f.isView &&
         !f.isPure
     }

{
    bytes blsPublicKey;
    require blsPublicKey.length == 32;

    uint256 dETHMintedBefore = dETHRewardsMintedForKnot(blsPublicKey);

    callFuncWithParams(f, e, blsPublicKey);

    uint256 dETHMintedAfter = dETHRewardsMintedForKnot(blsPublicKey);

    assert dETHMintedBefore <= dETHMintedAfter;
}

rule indexPointerBoundsKnotIndex(env e, method f, bytes knotId)
filtered {
        f ->
              f.selector != upgradeToAndCall(address,bytes).selector &&
              f.selector != upgradeTo(address).selector &&
              f.selector != createIndex(address).selector
    }
{
    require knotId.length == 32;

    require associatedIndexIdForKnot(knotId) <= indexPointer();

    callFuncWithParams(f, e, knotId);

    assert associatedIndexIdForKnot(knotId) <= indexPointer();
}

// description: the savETH index zero is owned by the savETH holders and any dETH can curate a savETH and therefore it does not have an associated owner
rule invariant_indexZeroCanNeverBeOwned(
    env e,
    method f,
    calldataarg args,
    bytes blsPubKey
)
filtered {
        f ->
              f.selector != upgradeToAndCall(address,bytes).selector &&
              f.selector != upgradeTo(address).selector
    }
{

    require blsPubKey.length == 32;
    require indexIdToOwner(0) == 0;
    require indexPointer() < max_uint256;

    callFuncWithParams(f, e, blsPubKey);

    assert indexIdToOwner(0) == 0;
}

// description: because zero index cannot be owned, it should not be possible to approve a spender to transfer the index from one account to another
rule invariant_indexZeroCanNeverBeApprovedForSpending(
    env e,
    method f,
    calldataarg args,
    bytes blsPubKey
)
filtered {
        f ->
              f.selector != upgradeToAndCall(address,bytes).selector &&
              f.selector != upgradeTo(address).selector
    }
{

    require blsPubKey.length == 32;
    require approvedIndexSpender(0) == 0;
    require indexPointer() < max_uint256;

    callFuncWithParams(f, e, blsPubKey);

    assert approvedIndexSpender(0) == 0;
}

// description: if you deposit and withdraw dETH in a single transaction you should expect same amount of tokens within the bounds of some precision loss (0 or 1 wei)
rule depositAndWithdrawResultsInTheSameNumberOfDETHTokens(env e) {
    address stakeHouse;
    bytes blsPubKey; require blsPubKey.length == 32;
    address indexOwner;

    uint256 dETHBalanceBefore = dETHToken.balanceOf(e,indexOwner);

    require knotDETHBalanceInIndex(associatedIndexIdForKnot(blsPubKey), blsPubKey) == 24000000000000000000 + dETHRewardsMintedForKnot(blsPubKey) && knotDETHBalanceInIndex(associatedIndexIdForKnot(blsPubKey), blsPubKey) < max_uint128;

    addKnotToOpenIndexAndWithdraw(e, stakeHouse, blsPubKey, indexOwner, indexOwner);

    uint256 dETHBalAfterWithdraw = dETHToken.balanceOf(e,indexOwner);

    uint256 indexId;
    depositAndIsolateKnotIntoIndex(e, stakeHouse, blsPubKey, indexOwner, indexId);

    assert dETHToken.balanceOf(e,indexOwner) == dETHBalanceBefore;
}