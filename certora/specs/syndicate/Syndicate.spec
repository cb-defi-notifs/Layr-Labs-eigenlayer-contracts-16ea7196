import "../../ComplexityCheck/erc20.spec"

methods {
    //// Regular methods
    totalETHReceived() returns (uint256) envfree
    isKnotRegistered(bytes) returns (bool) envfree
    getSameBytesArray(bytes) returns (bytes[])

    //// Resolving external calls
	//stakehouseuniverse, need to mock
	//stakeHouseKnotInfo(bytes) returns (address,address,address,uint256,uint256,bool) => NONDET
    //memberKnotToStakeHouse(bytes) returns (address) => NONDET // not used directly by Syndicate
    // stakehouse registry, need to mock
    //getMemberInfo(bytes) returns (address,uint256,uint16,bool) => NONDET // not used directly by Syndicate
	
    // slot registry
	// stakeHouseShareTokens(address stakeHouse) returns (address) => ghostFunc_stakeHouseShareTokens(stakeHouse)
	// currentSlashedAmountOfSLOTForKnot(bytes knot) returns (uint256) =>  ghostFunc_currentSlashedAmountOfSLOTForKnot(knot)
	// numberOfCollateralisedSlotOwnersForKnot(bytes knot) returns (uint256) =>  ghostFunc_numberOfCollateralisedSlotOwnersForKnot(knot)
	// getCollateralisedOwnerAtIndex(bytes memberId, uint256 index) returns (address) =>  ghostFunc_getCollateralisedOwnerAtIndex(memberId,index)
	// totalUserCollateralisedSLOTBalanceForKnot(address stakeHouse, address user, bytes memberId) returns (uint256) => ghostFunc_totalUserCollateralisedSLOTBalanceForKnot(stakeHouse,user,memberId)

    //// Harnessing
    // harnessed variables
    get_accruedEarningPerCollateralizedSlotOwnerOfKnot(bytes,address) returns (uint256) envfree
    get_totalETHProcessedPerCollateralizedKnot(bytes) returns (uint256) envfree
    get_sETHStakedBalanceForKnot(address,bytes) returns (uint256) envfree
    get_sETHTotalStakeForKnot(bytes) returns (uint256) envfree
    // harnessed functions
    // call_deRegisterKnots(bytes) 
    // call_stake(bytes[],uint256[],address) envfree
    // call_unstake(address,address,bytes[],uint256[]) envfree
    // call_claimAsStaker(address, bytes[]) envfree
    // call_claimAsCollateralizedSLOTOwner(address,bytes[]) envfree
    // call_registerKnotsToSyndicate(bytes)
    // call_addPriorityStakers(address)
    // call1_batchUpdateCollateralizedSlotOwnersAccruedETH(bytes)
    // call2_batchUpdateCollateralizedSlotOwnersAccruedETH(bytes,bytes)

    //// Summarizations
    /**
     * Proved batchUpdateCollateralizedSlotOwnersAccruedETH is equivalent to calling 
     * updateCollateralizedSlotOwnersAccruedETH twice
     * https://vaas-stg.certora.com/output/93493/26b008c032dc923cb10e/?anonymousKey=51e56e897be010ce553af6bc5fcbdc0478894620
     * Had to overapproximate stakeHouseKnotInfo which was causing reachability issues
     */
    batchUpdateCollateralizedSlotOwnersAccruedETH(bytes[]) => CONSTANT

}

//// Ghost variables used for summarization
// ghost mapping(bytes => mapping(address => mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => bool)))))) ghostMap_stakeHouseKnotInfo;

// ghost mapping(address => address) ghostMap_stakeHouseShareTokens;
// ghost mapping(bytes => uint256) ghostMap_currentSlashedAmountOfSLOTForKnot;
// ghost mapping(bytes => uint256) ghostMap_numberOfCollateralisedSlotOwnersForKnot;
// ghost mapping(bytes => mapping(uint256 => address)) ghostMap_getCollateralisedOwnerAtIndex;
// ghost mapping(address => mapping(address => mapping(bytes => uint256))) ghostMap_totalUserCollateralisedSLOTBalanceForKnot;

// function ghostFunc_stakeHouseShareTokensghost(address stakeHouse) returns address {
//     return ghostMap_stakeHouseShareTokens[stakeHouse];
// }
// function ghostFunc_currentSlashedAmountOfSLOTForKnotghost(bytes knot) returns uint256 {
//     return ghostMap_currentSlashedAmountOfSLOTForKnot[knot];
// }
// function ghostFunc_numberOfCollateralisedSlotOwnersForKnotghost(bytes knot) returns uint256  {
//     return ghostMap_numberOfCollateralisedSlotOwnersForKnot[knot];
// }
// function ghostFunc_getCollateralisedOwnerAtIndexghost(bytes memberId, uint256 index) returns address {
//     return ghostMap_getCollateralisedOwnerAtIndex[memberId][index];
// }
// function ghostFunc_totalUserCollateralisedSLOTBalanceForKnotghost(address stakeHouse, address user, bytes memberId) returns uint256 {
//     return ghostMap_totalUserCollateralisedSLOTBalanceForKnot[stakeHouse][user][memberId];
// }
// function ghostFlunc_stakeHouseKnotInfo(bytes knot) returns (address stakeHouse, address member, address slot, uint256 stake, uint256 slashedAmount, bool isRegistered) {
//     address stakeHouse; address member; address slot; uint256 stake; uint256 slashedAmount; bool isRegistered;
//     require ghostMap_stakeHouseKnotInfo[knot][stakeHouse][member][slot][stake][slashedAmount] == isRegistered;
    
// }
// ghost mapping(uint => mapping(uint => uint)) ghost_toValue
//     axiom ghost_toValue[];

// ghost mapping(address => mapping(uint => uint)) multiDim2;

definition notHarnessCall(method f) returns bool = true;
//     f.selector != call_deRegisterKnots(bytes).selector
//     && f.selector != call_stake(bytes,uint256,address).selector
//     && f.selector != call_unstake(address,address,bytes,uint256).selector
//     && f.selector != call_claimAsStaker(address,bytes).selector
//     && f.selector != call_claimAsCollateralizedSLOTOwner(address,bytes).selector
//     && f.selector != call_registerKnotsToSyndicate(bytes).selector
//     && f.selector != call_addPriorityStakers(address).selector;

/* P
    calling batchUpdateCollateralizedSlotOwnersAccruedETH is equivalent to calling updateCollateralizedSlotOwnersAccruedETH twice
*/
// rule batchEquivalence() {
//     bytes blsPubKey1;
//     bytes blsPubKey2;
//     storage initial = lastStorage;
//     env e;

//     call2_batchUpdateCollateralizedSlotOwnersAccruedETH(e, blsPubKey1, blsPubKey2);
    
//     uint256 totalETHProcessedPerCollateralizedKnot1batch = get_totalETHProcessedPerCollateralizedKnot(blsPubKey1);
//     uint256 getAccruedEarningPerCollateralizedSlotOwnerOfKnot1batch = get_accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKey1, e.msg.sender);
//     uint256 totalETHProcessedPerCollateralizedKnot2batch = get_totalETHProcessedPerCollateralizedKnot(blsPubKey2);
//     uint256 getAccruedEarningPerCollateralizedSlotOwnerOfKnot2batch = get_accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKey2, e.msg.sender);

//     updateCollateralizedSlotOwnersAccruedETH(e, blsPubKey1) at initial;
//     updateCollateralizedSlotOwnersAccruedETH(e, blsPubKey2);

//     uint256 totalETHProcessedPerCollateralizedKnot1 = get_totalETHProcessedPerCollateralizedKnot(blsPubKey1);
//     uint256 getAccruedEarningPerCollateralizedSlotOwnerOfKnot1 = get_accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKey1, e.msg.sender);
//     uint256 totalETHProcessedPerCollateralizedKnot2 = get_totalETHProcessedPerCollateralizedKnot(blsPubKey2);
//     uint256 getAccruedEarningPerCollateralizedSlotOwnerOfKnot2 = get_accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKey2, e.msg.sender);
    
//     assert totalETHProcessedPerCollateralizedKnot1 == totalETHProcessedPerCollateralizedKnot1batch &&
//         getAccruedEarningPerCollateralizedSlotOwnerOfKnot1 == getAccruedEarningPerCollateralizedSlotOwnerOfKnot1batch &&
//         totalETHProcessedPerCollateralizedKnot2 == totalETHProcessedPerCollateralizedKnot2batch &&
//         getAccruedEarningPerCollateralizedSlotOwnerOfKnot2 == getAccruedEarningPerCollateralizedSlotOwnerOfKnot2batch;
// }

/* P
    total eth received should only increase
*/
// rule totalEthReceivedMonotonicallyIncreases(method f) filtered {
//     f -> notHarnessCall(f)
// }{
    
//     uint256 totalEthReceivedBefore = totalETHReceived();

//     env e; calldataarg args;
//     f(e, args);

//     uint256 totalEthReceivedAfter = totalETHReceived();

//     assert totalEthReceivedAfter >= totalEthReceivedBefore, "total ether received must not decrease";
// }

/* P
    cant deregister an unregistered knot
*/
// rule canNotDegisterUnregisteredKnot(method f) filtered {
//     f -> notHarnessCall(f)
// } {
//     bytes knot; env e;
//     require !isKnotRegistered(knot);

//     call_deRegisterKnots@withrevert(e, knot);

//     assert lastReverted, "deRegisterKnots must revert if knot is not registered";
// }

/* P
    The sETH stake of a user must be less than or equal to the total sETH stake of the knot.
*/
invariant sETHSolvency(address user, bytes knot) 
    get_sETHStakedBalanceForKnot(user,knot) <= get_sETHTotalStakeForKnot(knot)
    filtered { f -> notHarnessCall(f) }

    ///// all eth received should split 50/50 between the two share types
    //// each share type is independent of the other, can't affect the other's collected eth

    ///// free floating slot is capped

    ///// free floating slot is not required to stake

rule sanity(method f) filtered { f -> notHarnessCall(f) } {
    env e; calldataarg args;
    f(e, args);
    assert false;
}
