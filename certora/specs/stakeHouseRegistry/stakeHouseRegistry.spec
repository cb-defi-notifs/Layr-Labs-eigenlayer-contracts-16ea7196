using StakeHouseAccessControls as access
using SlotSettlementRegistry as slotReg
using savETHRegistry as savETHReg

methods {
	memberKNOTIndexPointer() returns uint256 envfree
	getMemberInfo(bytes) returns (address,uint256,uint16,bool) envfree

	numberOfActiveKNOTsThatHaveNotRageQuit() returns (uint256) envfree => DISPATCHER(true)
	kick(bytes) => DISPATCHER(true)

	isCoreModule(address) returns bool envfree => DISPATCHER(true)
    access.isCoreModule(address) returns bool envfree

    activeSlotMintedInHouse(address) returns uint256 envfree => DISPATCHER(true)
    slotReg.activeSlotMintedInHouse(address) returns uint256 envfree

    activeCollateralisedSlotMintedInHouse(address) returns uint256 envfree => DISPATCHER(true)
    slotReg.activeCollateralisedSlotMintedInHouse(address) returns uint256 envfree

    totalDETHMintedWithinHouse(address) returns uint256 envfree => DISPATCHER(true)
    savETHReg.totalDETHMintedWithinHouse(address) returns uint256 envfree

    mintDETHReserves(address,bytes,uint256) => DISPATCHER(true)
    savETHReg.mintDETHReserves(address,bytes,uint256)

    exchangeRate(address) returns uint256 envfree => DISPATCHER(true)
    slotReg.exchangeRate(address) returns uint256 envfree

    circulatingSlot(address) returns uint256 envfree => DISPATCHER(true)
    slotReg.circulatingSlot(address) returns uint256 envfree

    stakeHouseCurrentSLOTSlashed(address) returns uint256 envfree => DISPATCHER(true)
    slotReg.stakeHouseCurrentSLOTSlashed(address) returns uint256 envfree

    redemptionRate(address) returns uint256 envfree => DISPATCHER(true)
    slotReg.redemptionRate(address) returns uint256 envfree

    slash(address,bytes,uint256,bool) => DISPATCHER(true)
    slotReg.slash(address,bytes,uint256,bool)

    currentSlashedAmountOfSLOTForKnot(bytes) returns uint256 envfree => DISPATCHER(true)
    slotReg.currentSlashedAmountOfSLOTForKnot(bytes) returns uint256 envfree
}

function invokeParametric(env e, method f) {
	if (f.isFallback) {
		calldataarg arg;
		f@withrevert(e, arg);
	} else if (f.selector == kick(bytes).selector) {
		bytes b;
		require b.length == 64;
		kick(e, b);
	} else if (f.selector == rageQuit(bytes).selector) {
		bytes b;
		require b.length == 64;
		rageQuit(e, b);
	} else {
		calldataarg arg;
		f(e, arg);
	}
}

// description: no matter how many knots in a house, total slot minted in house is 8 * num of knots that have not quit
invariant invariant_activeSlotMintedInHouseIsBasedOnNumberOfActiveKNOTsThatHaveNotRageQuit()
    slotReg.activeSlotMintedInHouse(currentContract) == (8000000000000000000 * numberOfActiveKNOTsThatHaveNotRageQuit())

// description: no matter how many knots in a house, total slot minted in house is a multiple of 8
invariant invariant_activeSlotMintedInHouseIsMultipleOfEight()
    (slotReg.activeSlotMintedInHouse(currentContract) % 8000000000000000000) == 0

// description: no matter how many knots in a house, total collateralised slot in house is 4 * numberOfActiveKNOTsThatHaveNotRageQuit
invariant invariant_activeCollateralisedSlotMintedInHouseIsBasedOnNumberOfActiveKNOTsThatHaveNotRageQuit()
    slotReg.activeCollateralisedSlotMintedInHouse(currentContract) == (4000000000000000000 * numberOfActiveKNOTsThatHaveNotRageQuit())

// description: no matter how many knots in a house, total collateralised slot in house is a multiple of 4
invariant invariant_activeCollateralisedSlotMintedInHouseIsAMultipleOfFour()
    (slotReg.activeCollateralisedSlotMintedInHouse(currentContract) % 4000000000000000000) == 0

// TODO - instate not working - will fix
//invariant invariant_circulatingSlotIsCorrectlyCalculatedBasedOnKnotsThatHaveNotRageQuitAndTotalSlashedAtHouseLevel(uint256 slashedAtHouseLevel)
//    slotReg.circulatingSlot(currentContract) == ((8000000000000000000 * numberOfActiveKNOTsThatHaveNotRageQuit()) - slashedAtHouseLevel)
//    {
//        preserved {
//            require slashedAtHouseLevel <= (4000000000000000000 * numberOfActiveKNOTsThatHaveNotRageQuit());
//            require slotReg.stakeHouseCurrentSLOTSlashed(currentContract) == slashedAtHouseLevel;
//        }
//    }

// description: as the dETH in the house increases, so does exchange rate in the slot registry
rule exchangeRateIncreasesAsDETHInHouseIncreases {
    env e;

    uint256 numberOfActiveKNOTs = numberOfActiveKNOTsThatHaveNotRageQuit();
    require numberOfActiveKNOTs >= 1;

    require savETHReg.totalDETHMintedWithinHouse(currentContract) == (24000000000000000000 * numberOfActiveKNOTs);
    assert slotReg.exchangeRate(currentContract) == 3000000000000000000;

    uint256 rewards;
    require rewards >= 100000000000000 && rewards <= max_uint32; // >= 0.0001 ETH

    bytes blsPubKey; require blsPubKey.length == 32;
    savETHReg.mintDETHReserves(e,currentContract,blsPubKey,rewards);

    assert savETHReg.totalDETHMintedWithinHouse(currentContract) == ((24000000000000000000 * numberOfActiveKNOTs) + rewards);

    uint256 rateAfter = slotReg.exchangeRate(currentContract);
    assert rateAfter == ( ((24000000000000000000 * numberOfActiveKNOTs) + rewards) / (8000000000000000000 * numberOfActiveKNOTs) );
}

// description: ensure that the base exchange rate is always 3:1 when there are no knots in the house after a rage quit
invariant invariant_houseExchangeRateIsThreeToOneWhenZeroKnotsInHouse()
    numberOfActiveKNOTsThatHaveNotRageQuit() == 0 => slotReg.exchangeRate(currentContract) == 3000000000000000000

// description: highlight all of the methods that increase the number of knots in the house
rule onlyAddMemberCanIncreaseIndexPointer(env e, method f) {
	uint256 oldValue = memberKNOTIndexPointer();

	invokeParametric(e, f);

	uint256 newValue = memberKNOTIndexPointer();

	assert newValue != oldValue => f.selector == addMember(address,bytes).selector;
}

// description: new knot will increase total number of knots in the house by one
rule newMemberIncreasesKnotPointerByOne {
    env e;

    address applicant;

    bytes memberId;
    require memberId.length == 64;

    uint256 oldValue = memberKNOTIndexPointer();

    addMember(e, applicant, memberId);

    uint256 newValue = memberKNOTIndexPointer();

    assert (newValue - oldValue == 1, "Pointer did not increase by one");
}

// description: a new knot must correctly record the depositor, index within the house, and that it is active
rule newMemberIsAssignedCorrectValues {
    env e;

    address applicant;

    // this should be 48 bytes but has to be 64 for now due to tool
    bytes memberId;
    require memberId.length == 64;

    addMember(e, applicant, memberId);

    uint256 currentIndexPointer = memberKNOTIndexPointer();

    address _applicant; uint256 _knotMemberIndex; uint16 _flags; bool _isActive;
    _applicant, _knotMemberIndex, _flags, _isActive = getMemberInfo(memberId);

    assert (_applicant == applicant, "Invalid applicant / depositor");
    assert (_knotMemberIndex == currentIndexPointer, "Invalid knot index");
    assert (_flags == 1, "Flags should be set to 1");
    assert (_isActive == true, "Member should be active");
}

// description: only core modules are allowed to call state changing methods in registry
rule invariant_nonCoreModuleShouldNotBeAbleToCallAnyStateChangeMethod(method f)
filtered {
     f ->
         f.selector != init(address).selector &&
         f.selector != setGateKeeper(address).selector &&
         f.selector != transferOwnership(address).selector &&
         f.selector != renounceOwnership().selector &&
         !f.isView &&
         !f.isPure
     }
{
    env e;

    require e.msg.sender != 0;

    bool isCore = access.isCoreModule(e.msg.sender);

    calldataarg arg;
    f@withrevert(e, arg);

    assert !isCore => lastReverted;
}
