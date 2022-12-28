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

// description: only core modules are allowed to call state changing methods in savETH registry
rule invariant_nonCoreModuleShouldNotBeAbleToCallAnyStateChangeMethod(method f)
filtered {
     f ->
         f.selector != init(address,address).selector &&
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
