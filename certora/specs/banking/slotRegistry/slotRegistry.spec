using StakeHouseRegistry as stakeHouseRegistry
using savETHRegistry as SavETHRegistry
using StakeHouseAccessControls as access

methods {
    dETHMintedInHouse(address) returns (uint256) envfree
    activeSlotMintedInHouse(address) returns (uint256) envfree
    exchangeRate(address) returns (uint256) envfree
    redemptionRate(address) returns (uint256) envfree
    stakeHouseShareTokens(address) returns (address) envfree // stakehouse address -> sETH token address
    shareTokensToStakeHouse(address) returns (address) envfree // sETH token address -> stakehouse
    knotSlotSharesMinted(bytes) returns (bool) envfree
    circulatingCollateralisedSlot(address) returns (uint256) envfree // house address -> (total collateralised SLOT - total slashed)
    circulatingSlot(address) returns (uint256) envfree // house address -> (total SLOT - total slashed)
    stakeHouseCurrentSLOTSlashed(address) returns (uint256) envfree // house address -> total slashed SLOT
    currentSlashedAmountOfSLOTForKnot(bytes) returns (uint256) envfree // knot -> total slashed SLOT
    totalUserCollateralisedSLOTBalanceInHouse(address, address) returns (uint256) envfree // house address -> user address -> collateralised SLOT
    totalUserCollateralisedSLOTBalanceForKnot(address, address, bytes) returns (uint256) envfree // house address -> user address -> collateralised SLOT
    isCollateralisedOwner(bytes,address) returns (bool) envfree // bls pub key -> user -> is collateralised slot owner
    numberOfCollateralisedSlotOwnersForKnot(bytes) returns (uint256) envfree
    getCollateralisedOwnerAtIndex(bytes,uint256) returns (address) envfree
    isUserEnabledForKnotWithdrawal(address,bytes) returns (bool) envfree

    isCoreModule(address) returns bool envfree => DISPATCHER(true)
    access.isCoreModule(address) returns bool envfree

    saveETHToDETHExchangeRate() => NONDET

    totalDETHMintedWithinHouse(address) returns uint256 envfree => DISPATCHER(true)
    SavETHRegistry.totalDETHMintedWithinHouse(address) returns uint256 envfree


    // StakeHouseRegistry
    numberOfActiveKNOTs() returns (uint256) envfree => DISPATCHER(true)
    stakeHouseRegistry.numberOfActiveKNOTs() returns uint256 envfree
    hasMemberRageQuit(bytes) => DISPATCHER(true)
    kick(bytes) => DISPATCHER(true)
    rageQuit(bytes) => DISPATCHER(true)

    // sETH summaries
    mint(address,uint256) => DISPATCHER(true)
    burn(address,uint256) => DISPATCHER(true)
}

function invokeParametric(env e, method f) {
    if (f.isFallback) {
        calldataarg arg;
        f@withrevert(e, arg);
    } else {
        calldataarg arg;
        f(e, arg);
    }
}

/// ----------
/// Rules
/// ----------

// description: this rule is all about checking balances are correctly reducing.
//              this is not checking whether the KNOT is eligible for rage quit via redemption rate rules.
//              therefore the assumption is that given it is eligible, do balances correctly reduce
rule rageQuitKnotClearsBalances {
    env e;

    address stakeHouse;
    bytes blsPubKey; require blsPubKey.length == 32;

    address collateralisedSlotOwnerOne;
    address collateralisedSlotOwnerTwo;
    address collateralisedSlotOwnerThree;
    address[] collateralisedSlotOwners = [
        collateralisedSlotOwnerOne,
        collateralisedSlotOwnerTwo,
        collateralisedSlotOwnerThree
    ];

    address freeFloatingSlotOwner;
    address savETHIndexOwner;
    uint256 amountOfETHInDepositQueue;

    uint256 numberOfCollateralisedSlotOwners = numberOfCollateralisedSlotOwnersForKnot(blsPubKey);
    require numberOfCollateralisedSlotOwners <= 3;

    uint256 ownerOneBalanceBefore = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collateralisedSlotOwnerOne, blsPubKey);
    uint256 ownerTwoBalanceBefore = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collateralisedSlotOwnerTwo, blsPubKey);
    uint256 ownerThreeBalanceBefore = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collateralisedSlotOwnerThree, blsPubKey);

    address ethRecipient;
    require isUserEnabledForKnotWithdrawal(ethRecipient, blsPubKey) == false;

    uint256 collatSLOTInHouseOwnerOneBefore = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, collateralisedSlotOwnerOne);
    uint256 collatSLOTInHouseOwnerTwoBefore = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, collateralisedSlotOwnerTwo);
    uint256 collatSLOTInHouseOwnerThreeBefore = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, collateralisedSlotOwnerThree);

    rageQuitKnotOnBehalfOf(
        e,
        stakeHouse,
        blsPubKey,
        ethRecipient,
        collateralisedSlotOwners,
        freeFloatingSlotOwner,
        savETHIndexOwner,
        amountOfETHInDepositQueue
    );

    uint256 ownerOneBalanceAfter = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collateralisedSlotOwnerOne, blsPubKey);
    assert ownerOneBalanceBefore > 0 => ownerOneBalanceAfter == 0;

    uint256 ownerTwoBalanceAfter = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collateralisedSlotOwnerTwo, blsPubKey);
    assert ownerTwoBalanceBefore > 0 => ownerTwoBalanceAfter == 0;

    uint256 ownerThreeBalanceAfter = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collateralisedSlotOwnerThree, blsPubKey);
    assert ownerThreeBalanceBefore > 0 => ownerThreeBalanceAfter == 0;

    uint256 collatSLOTInHouseOwnerOneAfter = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, collateralisedSlotOwnerOne);
    assert ownerOneBalanceBefore > 0 => collatSLOTInHouseOwnerOneBefore - collatSLOTInHouseOwnerOneAfter == ownerOneBalanceBefore;

    uint256 collatSLOTInHouseOwnerTwoAfter = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, collateralisedSlotOwnerTwo);
    assert ownerTwoBalanceBefore > 0 => collatSLOTInHouseOwnerTwoBefore - collatSLOTInHouseOwnerTwoAfter == ownerTwoBalanceBefore;

    uint256 collatSLOTInHouseOwnerThreeAfter = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, collateralisedSlotOwnerThree);
    assert ownerThreeBalanceBefore > 0 => collatSLOTInHouseOwnerThreeBefore - collatSLOTInHouseOwnerThreeAfter == ownerThreeBalanceBefore;

    assert isUserEnabledForKnotWithdrawal(ethRecipient, blsPubKey) == true;

    // see savETH registry spec to see burning of 24 dETH taking place
}

// description: ensure sETH deployment is recorded correctly
rule deployingStakeHouseTokenSetsUpMappingCorrectly {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    deployStakeHouseShareToken(e, stakeHouse);

    address tokenAddress = stakeHouseShareTokens(stakeHouse);
    assert (shareTokensToStakeHouse(tokenAddress) == stakeHouse, "reverse lookup not set up");
}

// description: ensure SLOT can only be minted once
rule newKnotSetsMintedFlagToTrue {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 64;

    address recipient;
    require recipient != 0;

    bool mintedBefore = knotSlotSharesMinted(blsPubKey);
    require mintedBefore == false;

    mintSLOTAndSharesBatch(e, stakeHouse, blsPubKey, recipient);

    bool mintedAfter = knotSlotSharesMinted(blsPubKey);
    assert (mintedAfter == true, "Minted is false");
}

// description: check that exactly 4 SLOT is collateralised for knot
rule newKNOTIncreasesCollateralisedSLOTByFourForRecipient {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 64;

    address recipient;
    require recipient != 0;

    uint256 slotForKnotBefore = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, recipient, blsPubKey);
    require slotForKnotBefore == 0;

    uint256 slotForReceipientAtHouseLevelBefore = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, recipient);
    require slotForReceipientAtHouseLevelBefore < 1000000000000000000000000;

    uint256 numOfOwners = numberOfCollateralisedSlotOwnersForKnot(blsPubKey);
    require numOfOwners == 0;

    mintSLOTAndSharesBatch(e, stakeHouse, blsPubKey, recipient);

    uint256 numOfOwnersAfter = numberOfCollateralisedSlotOwnersForKnot(blsPubKey);
    require numOfOwnersAfter == 1;

    uint256 slotForKnotAfter = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, recipient, blsPubKey);
    uint256 slotForReceipientAtHouseLevelAfter = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, recipient);

    assert slotForKnotAfter - slotForKnotBefore == 4000000000000000000;
    assert slotForReceipientAtHouseLevelAfter - slotForReceipientAtHouseLevelBefore == 4000000000000000000;

    address collatOwner = getCollateralisedOwnerAtIndex(blsPubKey, 0);
    assert collatOwner == recipient;
}

// description: collateralised SLOT owner only added once
rule whenAlreadyCollateralisedOwnerForKnotTopupSLOTDoesNotAddOwnerAgain {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 64;

    uint256 amount;

    address recipient;
    require recipient != 0;

    bool isCollateralisedOwnerBefore = isCollateralisedOwner(blsPubKey,recipient);
    require isCollateralisedOwnerBefore == true;

    uint256 numOfCollateralisedOwnersBefore = numberOfCollateralisedSlotOwnersForKnot(blsPubKey);

    buySlashedSlot(e, stakeHouse, blsPubKey, amount, recipient);

    uint256 numOfCollateralisedOwnersAfter = numberOfCollateralisedSlotOwnersForKnot(blsPubKey);

    assert numOfCollateralisedOwnersAfter == numOfCollateralisedOwnersBefore;
}

// description: slashing is cleared down when topping up slashed SLOT
rule toppingUpSlashedSlotUpdatesSlashedAtHouseAndKnotLevel {
    env e;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 64;

    address recipient;
    require recipient != 0;

    uint256 collatSlotAtHouseForRecipientBefore = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, recipient);
    require collatSlotAtHouseForRecipientBefore == 0;

    uint256 collatSlotForKnotForRecipientBefore = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse,recipient,blsPubKey);
    require collatSlotForKnotForRecipientBefore == 0;

    uint256 houseSlashedBefore = stakeHouseCurrentSLOTSlashed(stakeHouse);
    require houseSlashedBefore > 0 && houseSlashedBefore % 4000000000000000000 == 0;

    uint256 knotSlashedBefore = currentSlashedAmountOfSLOTForKnot(blsPubKey);
    require knotSlashedBefore == 4000000000000000000;

    uint256 amount;
    require amount == 4000000000000000000;

    buySlashedSlot(e, stakeHouse, blsPubKey, amount, recipient);

    uint256 collatSlotAtHouseForRecipientAfter = totalUserCollateralisedSLOTBalanceInHouse(stakeHouse, recipient);
    assert collatSlotAtHouseForRecipientAfter == amount;

    uint256 collatSlotForKnotForRecipientAfter = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse,recipient,blsPubKey);
    assert collatSlotForKnotForRecipientAfter == amount;

    uint256 houseSlashedAfter = stakeHouseCurrentSLOTSlashed(stakeHouse);
    assert houseSlashedAfter == houseSlashedBefore - amount;

    uint256 knotSlashedAfter = currentSlashedAmountOfSLOTForKnot(blsPubKey);
    assert knotSlashedAfter == 0;
}

// description: check slashing is correctly recorded in storage
rule slashingIsCorrectlyRecorded {
    env e;

    address stakeHouse;

    bytes blsPubKey; require blsPubKey.length == 64;

    uint256 currentSlashedBefore = currentSlashedAmountOfSLOTForKnot(blsPubKey);

    //uint256 slashedAtHouseLevelBefore = stakeHouseCurrentSLOTSlashed(stakeHouse);

    uint256 amount;
    bool isKickRequired;

    slash(e, stakeHouse, blsPubKey, amount, isKickRequired);

    uint256 currentSlashedAfter = currentSlashedAmountOfSLOTForKnot(blsPubKey);

    uint256 slashedAtHouseLevelAfter = stakeHouseCurrentSLOTSlashed(stakeHouse);

    assert currentSlashedAfter == (currentSlashedBefore + amount), "Slashing did not increase by the correct amount";
    assert currentSlashedAfter <= 4000000000000000000, "Slashing is more than 4"; // slashing for a KNOT never exceeds 4 SLOT
    //assert slashedAtHouseLevelAfter == (slashedAtHouseLevelBefore + amount);// slashing at house level increased by correct amount

    //uint256 slotForKnotAfter = totalUserCollateralisedSLOTBalanceForKnot(stakeHouse, collatOwner, blsPubKey);
    //assert slotForKnotAfter == (4000000000000000000 - (currentSlashed + amount));
}

// description: ensure data integrity when slashing and buy slot. Ensure no 'slash' is left behind
rule noSlashingIsRecordedAtHouseLevelWhenSlashingAndToppingUpInOneTX {
      env e;

      address stakeHouse; require stakeHouse != 0;

      bytes memberId; require memberId.length == 64;

      uint256 slashAmount;
      require slashAmount > 0 && slashAmount <= 3800000000000000000;

      uint256 currentSlotSlashedBefore = stakeHouseCurrentSLOTSlashed(stakeHouse);
      require currentSlotSlashedBefore <= 116000000000000000000000000; // less than 116m ether

      slashAndBuySlot(e, stakeHouse, memberId, e.msg.sender, slashAmount, slashAmount, false);

      uint256 currentSlotSlashedAfter = stakeHouseCurrentSLOTSlashed(stakeHouse);

      assert (currentSlotSlashedAfter - currentSlotSlashedBefore == 0, "Net slashed amount at house level was not zero");
}

// description: No minting of dETH is triggered when restoring the health of the knot by topping up slashed amount
rule toppingUpSlotNeverInflatesDETH {
    env e;

    address stakeHouse; require stakeHouse != 0;

    bytes blsPubKey; require blsPubKey.length == 64;

    uint256 mintedWithinHouseBefore = SavETHRegistry.totalDETHMintedWithinHouse(stakeHouse);

    uint256 amount;
    buySlashedSlot(e, stakeHouse, blsPubKey, amount, e.msg.sender);

    uint256 mintedWithinHouseAfter = SavETHRegistry.totalDETHMintedWithinHouse(stakeHouse);
    assert mintedWithinHouseAfter == mintedWithinHouseBefore;
}

// description: most methods don't adjust the total collateralised SLOT for house state
rule invariant_totalMintedCollateralisedSlotAtHouseLevelStaysTheSame(method f)
filtered { f ->
            f.selector != slash(address,bytes,uint256,bool).selector &&
            f.selector != slashAndBuySlot(address,bytes,address,uint256,uint256,bool).selector &&
            f.selector != buySlashedSlot(address,bytes,uint256,address).selector &&
            f.selector != upgradeTo(address).selector &&
            f.selector != upgradeToAndCall(address,bytes).selector &&
            f.selector != mintSLOTAndSharesBatch(address,bytes,address).selector &&
            f.selector != rageQuitKnotOnBehalfOf(address,bytes,address,address[],address,address,uint256).selector &&
            f.selector != init(address,address).selector
        }
{
    env e;

    address stakeHouse; require stakeHouse != 0;

    uint256 totalCollateralisedSlotBefore = stakeHouseCurrentSLOTSlashed(stakeHouse);
    require totalCollateralisedSlotBefore < max_uint128;

    calldataarg arg;
    f(e, arg);

    uint256 totalCollateralisedSlotAfter = stakeHouseCurrentSLOTSlashed(stakeHouse);

    assert (totalCollateralisedSlotAfter == totalCollateralisedSlotBefore, "collateralised SLOT invariant violated");
}

// description: the user collateralised vault balance for a knot cannot exceed more than 4 SLOT
rule invariant_slotBalanceInVaultIsNeverMoreThanFour(env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address,bytes).selector &&
         !f.isFallback
     }
{
   address user;
   address house;
   bytes blsPubKey; require blsPubKey.length == 32;

   uint256 currentSlashed = currentSlashedAmountOfSLOTForKnot(blsPubKey);
   require currentSlashed <= 4000000000000000000;
   require totalUserCollateralisedSLOTBalanceForKnot(house, user, blsPubKey) == (4000000000000000000 - currentSlashed);
   //todo - check what requires can be removed

   if (f.selector == buySlashedSlot(address,bytes,uint256,address).selector) {
     uint256 amount;
     buySlashedSlot(e, house, blsPubKey, amount, user);
   } else if (f.selector == slashAndBuySlot(address,bytes,address,uint256,uint256,bool).selector) {
     uint256 slashAmount;
     uint256 buyAmount;
     bool isKickRequired;

     require numberOfCollateralisedSlotOwnersForKnot(blsPubKey) == 1; // todo - make stronger by supporting at least 2
     require getCollateralisedOwnerAtIndex(blsPubKey,0) == user;

     slashAndBuySlot(e, house, blsPubKey, user, slashAmount, buyAmount, isKickRequired);
   } else if (f.selector == mintSLOTAndSharesBatch(address,bytes,address).selector) {
     require totalUserCollateralisedSLOTBalanceForKnot(house, user, blsPubKey) == 0;
     mintSLOTAndSharesBatch(e,house,blsPubKey,user);
   } else if (f.selector == markUserKnotAsWithdrawn(address,bytes).selector) {
     markUserKnotAsWithdrawn(e, user, blsPubKey);
   } else if (f.selector == rageQuitKnotOnBehalfOf(address,bytes,address,address[],address,address,uint256).selector) {
     rageQuitKnotOnBehalfOf(e,house,blsPubKey,user,[user],user,user,0);
   } else if (f.selector == slash(address,bytes,uint256,bool).selector) {
     uint256 slashAmount;
     bool isKickRequired;
     slash(e,house,blsPubKey,slashAmount,isKickRequired);
   } else {
     calldataarg arg;
     f(e, arg);
   }

   assert totalUserCollateralisedSLOTBalanceForKnot(house, user, blsPubKey) <= 4000000000000000000;
}
