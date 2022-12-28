using StakeHouseAccessControls as accessControls
using dETH as dETHToken
using SlotSettlementRegistry as slotRegistry
using sETH as sETHToken
using savETHRegistry as savETHReg

methods {
    // only need to declare env free
    stakeHouseKNOTIndexPointer() returns uint256 envfree
    memberKnotToStakeHouse(bytes) returns address envfree
    knotIndexToStakeHouse(uint256) returns address envfree
    stakeHouseToKNOTIndex(address) returns uint256 envfree

    numberOfAccounts() returns uint256 envfree => DISPATCHER(true)
    createIndex(address) returns uint256 => DISPATCHER(true)
    addMember(address,bytes) => DISPATCHER(true)
    mintSaveETHBatchAndDETHReserves(address,bytes,uint256) => DISPATCHER(true)
    mintSLOTAndSharesBatch(address,bytes,address) => DISPATCHER(true)
    deployStakeHouseShareToken(address) => DISPATCHER(true)
    mintBrand(string,address,bytes) => DISPATCHER(true)
    rageQuitKnotOnBehalfOf(address,bytes,address,address[],address,address,uint256) => DISPATCHER(true)
    associateSlotWithBrand(uint256,bytes) => DISPATCHER(true)

    associatedIndexIdForKnot(bytes) returns uint256 envfree => DISPATCHER(true)
    savETHReg.associatedIndexIdForKnot(bytes) returns uint256 envfree

    knotDETHBalanceInIndex(uint256,bytes) returns uint256 envfree => DISPATCHER(true)
    savETHReg.knotDETHBalanceInIndex(uint256,bytes) returns uint256 envfree
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

// description: when creating a knot, the dETH circulating supply should increase by 24 and SLOT by 8 via vault and sETH
rule joiningAHouseMintsTheCorrectBatchOfTokens {
    env e;

    address house;
    bytes blsPubKey; require blsPubKey.length == 32;

    address applicant;
    uint256 brandTokenId;
    uint256 savETHIndexId;

    env e2;
    uint256 totalSupply = dETHToken.totalSupply(e2);

    env e3;
    require slotRegistry.totalUserCollateralisedSLOTBalanceForKnot(e3, house, applicant, blsPubKey) == 0;

    env e4;
    uint256 sETHTotalSupply = sETHToken.totalSupply(e4);
    require sETHTotalSupply <= max_uint256 - 12000000000000000000;

    addMemberToExistingHouse(
        e,
        house,
        blsPubKey,
        applicant,
        brandTokenId,
        savETHIndexId
    );

    assert savETHReg.associatedIndexIdForKnot(blsPubKey) == savETHIndexId;
    assert savETHReg.knotDETHBalanceInIndex(savETHIndexId, blsPubKey) == 24000000000000000000;

    env e5;
    uint256 totalSupplyAfter = dETHToken.totalSupply(e5);
    assert totalSupplyAfter == totalSupply;

    uint256 sETHTotalSupplyAfter = sETHToken.totalSupply(e4);
    assert sETHTotalSupplyAfter == sETHTotalSupply + 12000000000000000000;

    assert slotRegistry.totalUserCollateralisedSLOTBalanceForKnot(e3, house, applicant, blsPubKey) == 4000000000000000000;
}

// description: Each deployment of a Stakehouse increases the total stakehouse pointer correctly
rule numberOfStakeHousesIncreases {
    env e;

    address depositor;
    uint256 buildingTypeId;
    string ticker;
    bytes blsPublicKey;
    require e.msg.sender != 0;
    require depositor == e.msg.sender;

    require buildingTypeId > 1 && buildingTypeId <= 6;
	require ticker.length <= 5;
    require blsPublicKey.length <= 64;

    uint256 oldNumberOfHouses = stakeHouseKNOTIndexPointer();
    require oldNumberOfHouses != max_uint256;

    uint256 savETHIndex;

	newStakeHouse(e, depositor, ticker, blsPublicKey, savETHIndex);

    uint256 newNumberOfHouses = stakeHouseKNOTIndexPointer();

    assert (newNumberOfHouses == (oldNumberOfHouses + 1), "num of houses did not increment");
}

// description: The correct index ID is appointed to the newly deployed house (house coordinates are formed correctly)
rule newHouseAssociatedWithCurrentIndex {
    env e;

    address depositor;
    uint256 buildingTypeId;
    string ticker;
    bytes blsPublicKey;
    require e.msg.sender != 0;
    require depositor == e.msg.sender;

    require buildingTypeId > 1 && buildingTypeId <= 6;
	require ticker.length <= 5;
    require blsPublicKey.length <= 64;

    uint256 oldNumberOfHouses = stakeHouseKNOTIndexPointer();
    require oldNumberOfHouses != max_uint256;

    uint256 savETHIndex;

	address stakehouse = newStakeHouse(e, depositor, ticker, blsPublicKey, savETHIndex);

    uint256 newNumberOfHouses = stakeHouseKNOTIndexPointer();
    address associatedHouse = knotIndexToStakeHouse(newNumberOfHouses);

    uint256 associatedIndex = stakeHouseToKNOTIndex(stakehouse);

    assert (associatedHouse == stakehouse, "House not associated with correct index");
    assert (associatedIndex == newNumberOfHouses, "House indexes dont match");
}

// description: Total number of houses is static when adding a member to a house (pointer only increases on house creation)
rule numberOfStakeHousesStaysStaticWhenAddingAMemberToAnExistingHouse {
    env e;

    address stakeHouse;
    bytes blsPublicKey;
    address depositor;
	uint256 brandTokenId;

    require blsPublicKey.length <= 64;

    uint256 savETHIndex;

    uint256 oldNumberOfHouses = stakeHouseKNOTIndexPointer();
	addMemberToExistingHouse(e, stakeHouse, blsPublicKey, depositor, brandTokenId, savETHIndex);
    uint256 newNumberOfHouses = stakeHouseKNOTIndexPointer();

    assert newNumberOfHouses == oldNumberOfHouses;
}

// description: Total number of houses is static when adding a member to a house (pointer only increases on house creation). Same as above but for creating a brand
rule numberOfStakeHousesStaysStaticWhenAddingAMemberToAnExistingHouseAndCreatingABrand {
    env e;

    address stakeHouse;
    bytes blsPublicKey;
    address depositor;
    string ticker;
    uint256 buildingTypeId;

	require ticker.length <= 5;
	require blsPublicKey.length <= 64;

	uint256 savETHIndex;

    uint256 oldNumberOfHouses = stakeHouseKNOTIndexPointer();
	addMemberToHouseAndCreateBrand(e, stakeHouse, blsPublicKey, depositor, ticker, savETHIndex);
    uint256 newNumberOfHouses = stakeHouseKNOTIndexPointer();

    assert newNumberOfHouses == oldNumberOfHouses;
}

// description: New knot is correctly assigned to the chosen Stakehouse registry (including when house is created)
rule calling_newStakeHouse_correctlySetsUpMemberHouseMapping {
    env e;

    address depositor;
    uint256 buildingTypeId;
    string ticker;
    bytes blsPublicKey;
    require e.msg.sender != 0;
    require depositor == e.msg.sender;

    require buildingTypeId > 1 && buildingTypeId <= 6;
	require ticker.length == 5;
    require blsPublicKey.length == 64;

    uint256 savETHIndex;

	address stakeHouse = newStakeHouse(e, depositor, ticker, blsPublicKey, savETHIndex);

    address associatedHouse = memberKnotToStakeHouse(blsPublicKey);
    assert (associatedHouse == stakeHouse, "KNOT is not associated with the expected house");
}

// description: New knot is correctly assigned to the chosen Stakehouse registry (including when house is created)
rule calling_addMemberToExistingHouse_correctlySetsUpMemberHouseMapping {
    // whenever a KNOT is added to a house, we record what house the KNOT is added to at the universe level so that we block
    // a member being added to more than one house

    env e;

    address stakeHouse;
    bytes blsPublicKey;
    address depositor;
    uint256 brandTokenId;

    require blsPublicKey.length == 64;

    uint256 savETHIndex;

    addMemberToExistingHouse(e, stakeHouse, blsPublicKey, depositor, brandTokenId, savETHIndex);

    address associatedHouse = memberKnotToStakeHouse(blsPublicKey);
    assert (associatedHouse == stakeHouse, "KNOT is not associated with the expected house");
}

// description: New knot is correctly assigned to the chosen Stakehouse registry (including when house is created)
rule calling_addMemberToHouseAndCreateBrand_correctlySetsUpMemberHouseMapping {
    // whenever a KNOT is added to a house, we record what house the KNOT is added to at the universe level so that we block
    // a member being added to more than one house

    env e;

    address stakeHouse;
    bytes blsPublicKey;
    address depositor;
    string ticker;
    uint256 buildingTypeId;

    require ticker.length == 5;
    require blsPublicKey.length == 64;

    uint256 savETHIndex;

    addMemberToHouseAndCreateBrand(e, stakeHouse, blsPublicKey, depositor, ticker, savETHIndex);

    address associatedHouse = memberKnotToStakeHouse(blsPublicKey);
    assert (associatedHouse == stakeHouse, "KNOT is not associated with the expected house");
}

// description: only core modules are allowed to call state changing methods in savETH registry
rule invariant_nonCoreModuleShouldNotBeAbleToCallAnyStateChangeMethod(method f)
filtered {
     f ->
         f.selector != init(
                        address,
                        address,
                        address,
                        address,
                        address,
                        address,
                        address,
                        address,
                        address,
                        address,
                        address
                       ).selector &&
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address,bytes).selector &&
         !f.isView &&
         !f.isPure
     }
{
    env e;

    require e.msg.sender != 0;

    env e2;
    bool isCore = accessControls.isCoreModule(e2, e.msg.sender);
    require isCore == false;

    calldataarg arg;
    address house;
    bytes blsPubKey;
    require blsPubKey.length == 32;

    if (f.isFallback) {
        f@withrevert(e, arg);
    } else if (f.selector == rageQuitKnot(address,bytes,address,uint256).selector) {
        address quitter;
        uint256 amountInQueue;
        rageQuitKnot@withrevert(e, house, blsPubKey, quitter, amountInQueue);
    } else if (f.selector == newStakeHouse(address,string,bytes,uint256).selector) {
        address summoner;
        string ticker;
        require ticker.length == 5;
        newStakeHouse@withrevert(e, summoner, ticker, blsPubKey, 0);
    } else if (f.selector == addMemberToHouseAndCreateBrand(address,bytes,address,string,uint256).selector) {
        address applicant;
        string ticker;
        require ticker.length == 5;
        uint256 savETHIndex;
        addMemberToHouseAndCreateBrand@withrevert(e, house, blsPubKey, applicant, ticker, savETHIndex);
    } else if (f.selector == addMemberToExistingHouse(address,bytes,address,uint256,uint256).selector) {
        address applicant;
        uint256 brandTokenId;
        uint256 savETHIndex;
        addMemberToExistingHouse@withrevert(e, house, blsPubKey, applicant, brandTokenId, savETHIndex);
    }

    assert lastReverted;
}

ghost countAllKnotsInTheUniverse() returns mathint {
    init_state axiom countAllKnotsInTheUniverse() == 0;
}

hook Sstore memberKnotToStakeHouse[KEY bytes knotId] address knotCount
(address oldKnotCount) STORAGE {
  havoc countAllKnotsInTheUniverse assuming countAllKnotsInTheUniverse@new() == countAllKnotsInTheUniverse@old() + 1;
}

/// description: there are not more houses than registered knots (this does not account for rage quit knots and does not need to)
invariant invariant_universeHasLessThanOrEqualStakehousesThanKnots()
    stakeHouseKNOTIndexPointer() <= countAllKnotsInTheUniverse()

    filtered {
             f ->
                 f.selector != upgradeTo(address).selector &&
                 f.selector != upgradeToAndCall(address, bytes).selector
        }

/// description: there cannot be more houses than accounts in the universe
invariant invariant_numberOfStakehousesUpperBoundedByNumberOfAccounts()
    numberOfAccounts() >= stakeHouseKNOTIndexPointer()

    filtered {
         f ->
             f.selector != upgradeTo(address).selector &&
             f.selector != upgradeToAndCall(address, bytes).selector
    }

    {
            preserved {
                require numberOfAccounts() < 10000000000;
            }
    }

/// description: there can not be more knots than accounts in the universe
invariant invariant_numberOfKnotsUpperBoundedByNumberOfAccounts()
    numberOfAccounts() >= countAllKnotsInTheUniverse()

    filtered {
         f ->
             f.selector != upgradeTo(address).selector &&
             f.selector != upgradeToAndCall(address, bytes).selector
    }

    {
            preserved {
                require numberOfAccounts() < 10000000000;
            }
    }
