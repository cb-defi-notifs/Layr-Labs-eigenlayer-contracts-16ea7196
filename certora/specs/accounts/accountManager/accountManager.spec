using StakeHouseAccessControls as access
using StakeHouseUniverse as universe
using savETHRegistry as indexRegistry

methods {
	blsPublicKeyToLifecycleStatus(bytes) returns uint8 envfree
	numberOfAccounts() returns uint256 envfree
	addressNCompletedPhase1(uint256) returns bool envfree
	blsPubKeyToAccountArrayIndex(bytes) returns uint256 envfree
	universe.numberOfStakeHouses() returns uint256 envfree
	markUserKnotAsWithdrawn(address, bytes) => DISPATCHER(true)
	compareAccountSignaturesByIndex(uint, uint) returns bool envfree
	compareKnotIds(bytes, bytes) returns bool envfree
	getAccountDepositBlockByIndex(uint256) returns uint256 envfree
	getAccountDepositBlockByKnotId(bytes) returns uint256 envfree
	getCurrentBlock() returns uint256

	isCoreModule(address) returns bool envfree => DISPATCHER(true)
    access.isCoreModule(address) returns bool envfree

    /// Irrelevant function summary
    newStakeHouse(address, string, bytes, uint256) returns address => DISPATCHER(true)
    createIndex(address) returns uint256 => NONDET
    addMember(address, bytes) => DISPATCHER(true)
    mintSaveETHBatchAndDETHReserves(address, bytes, uint256) returns address => NONDET
    mintSLOTAndSharesBatch(address, bytes, address) => NONDET
    mintBrand(string, address, bytes) returns uint256 => NONDET
    associateSlotWithBrand(uint256, bytes) => NONDET
    rageQuitKnotOnBehalfOf(address, bytes, address, address[], address, address, uint256) => DISPATCHER(true)
    rageQuitKnot(address, bytes, address, uint256) => DISPATCHER(true)

    indexIdToOwner(uint256) returns address envfree => DISPATCHER(true)
    indexRegistry.indexIdToOwner(uint256) returns address envfree

    knotdETHSharesMinted(bytes) returns bool envfree => DISPATCHER(true)
    indexRegistry.knotdETHSharesMinted(bytes) returns bool envfree

    universe.memberKnotToStakeHouse(bytes) returns address envfree
    memberKnotToStakeHouse(bytes) returns address envfree => DISPATCHER(true)
}

function invokeParametric(env e, method f) {
    bytes knotId;
    require knotId.length <= 7;

    callFuncWithParams(f, e, knotId);
}

/// description: Making sure that the only status increment possible is 1
rule registerInitialsIncrementsLifecycleStatusByOne {
	env e;

	address depositor;

	bytes blsPublicKey;
	require blsPublicKey.length == 64;

	bytes blsSignature;
	require blsSignature.length == 64;

    uint8 lifecycleStatusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

	registerValidatorInitials(e, depositor, blsPublicKey, blsSignature);

	uint8 lifecycleStatus = blsPublicKeyToLifecycleStatus(blsPublicKey);

	assert lifecycleStatus == 1 && lifecycleStatusBefore == 0; // INITIALS_REGISTERED is 1
}

/// description: Making sure that the only status increment possible is 1
rule createStakehouseIncrementsLifecycleStatusByOne {
    env e;

	address depositor;

	bytes blsPublicKey;
	require blsPublicKey.length == 64;

	string ticker;
	require ticker.length >= 3 && ticker.length <= 5;

	uint256 buildingId;
	uint256 savETHIndexId;

    uint8 lifecycleStatusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

	createStakehouse(e, depositor, blsPublicKey, ticker, savETHIndexId);

	uint8 lifecycleStatus = blsPublicKeyToLifecycleStatus(blsPublicKey);

	assert lifecycleStatus == 3 && lifecycleStatusBefore == 2; // TOKENS_MINTED is 3
}

/// description: Making sure that the only status increment possible is 1
rule joinStakehouseIncrementsLifecycleStatusByOne {
    env e;

	address depositor;

	bytes blsPublicKey;
	require blsPublicKey.length == 64;

	address stakeHouse;

	uint256 brandId;
	uint256 savETHIndexId;

    uint8 lifecycleStatusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

	joinStakehouse(e, depositor, blsPublicKey, stakeHouse, brandId, savETHIndexId);

	uint8 lifecycleStatus = blsPublicKeyToLifecycleStatus(blsPublicKey);

	assert lifecycleStatus == 3 && lifecycleStatusBefore == 2; // TOKENS_MINTED is 3
}

/// description: Making sure that the only status increment possible is 1
rule joinStakehouseAndCreateBrandIncrementsLifecycleStatusByOne {
    env e;

	address depositor;

	bytes blsPublicKey;
	require blsPublicKey.length == 64;

	address stakeHouse;

	string ticker;
    require ticker.length >= 3 && ticker.length <= 5;

    uint256 buildingId;

	uint256 savETHIndexId;

    uint8 lifecycleStatusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

	joinStakeHouseAndCreateBrand(e, depositor, blsPublicKey, ticker, stakeHouse, savETHIndexId);

	uint8 lifecycleStatus = blsPublicKeyToLifecycleStatus(blsPublicKey);

	assert lifecycleStatus == 3 && lifecycleStatusBefore == 2; // TOKENS_MINTED is 3
}

/// description: Checking if account is pushed correctly into the accounts array in AccountManager
rule elementIsPushed {
    env e;

	address depositor;

	bytes blsPublicKey;
	require blsPublicKey.length == 64;

	bytes blsSignature;
	require blsSignature.length == 64;

	uint256 oldAccountsLength = numberOfAccounts();

	registerValidatorInitials(e, depositor, blsPublicKey, blsSignature);

	uint256 newAccountsLength = numberOfAccounts();

	assert newAccountsLength == oldAccountsLength + 1;
}

/// description: Account array index correctness checks. Here we check if last registered account index is equal the account count
rule accountArrayIndexSetCorrectly(env e, address depositor, bytes blsPublicKey, bytes blsSignature) {
    require blsPublicKey.length == 64;
    require blsSignature.length == 64;

    registerValidatorInitials(e, depositor, blsPublicKey, blsSignature);

    uint256 index = blsPubKeyToAccountArrayIndex(blsPublicKey);
    uint256 accountCount = numberOfAccounts();

    assert (index == accountCount, "Account count not equal to the index");
}

ghost mapArrayIndexToKnotId(uint256) returns bytes;



/// description: Joining stakehouse assigns correct index owner in the index registry
rule joiningStakehouseAssignsCorrectOwner {
    env e;

    address depositor;

    bytes blsPublicKey;
    require blsPublicKey.length == 64;

    address stakeHouse;

    uint256 brandId;
    uint256 savETHIndexId;

    uint8 lifecycleStatusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

    require indexRegistry.indexIdToOwner(savETHIndexId) != depositor;

    joinStakehouse(e, depositor, blsPublicKey, stakeHouse, brandId, savETHIndexId);

    assert indexRegistry.indexIdToOwner(savETHIndexId) == depositor;
}

/// description: Helper function to isolate the blsPublicKey parameter
function callFuncWithParams(method f, env e, bytes blsPublicKey) {

    address depositor;
    bytes blsSignature;
    bytes ciphertext;
    bytes aesEncryptorKey;
    bytes32 depositContractRoot;
    string ticker;
    uint256 indexId;
    uint256 brandTokenId;
    address stakehouse;
    uint256 amountOfETHInDepositQueue;
    bytes withdrawalCredentials;
    bool slashed;
    uint64 epoch;

    require withdrawalCredentials.length < 32;
    require ticker.length < 32;
    require blsSignature.length == 96;
    require ciphertext.length == 32;
    require aesEncryptorKey.length == 32;
    require indexId < 10000000000;
    require brandTokenId < 10000000000;
    require amountOfETHInDepositQueue < max_uint256;
    require epoch < max_uint64;

    if (f.selector == registerValidatorInitials(address,bytes,bytes).selector) {
        registerValidatorInitials(e, depositor, blsPublicKey, blsSignature);
    }

    else if (f.selector == registerDeposit(address,bytes,bytes,bytes,bytes32).selector) {
        registerDeposit(e, depositor, blsPublicKey, ciphertext, aesEncryptorKey, depositContractRoot);
    }

    else if (f.selector == createStakehouse(address,bytes,string,uint256).selector) {
        createStakehouse(e, depositor, blsPublicKey, ticker, indexId);
    }

    else if (f.selector == joinStakehouse(address,bytes,address,uint256,uint256).selector) {
        joinStakehouse(e, depositor, blsPublicKey, stakehouse, brandTokenId, indexId);
    }

    else if (f.selector == joinStakeHouseAndCreateBrand(address,bytes,string,address,uint256).selector) {
        joinStakeHouseAndCreateBrand(e, depositor, blsPublicKey, ticker, stakehouse, indexId);
    }

    else if (f.selector == flattenRageQuitKnot(address,bytes,address,uint256,bytes,bool,uint64[]).selector) {
        uint64 activeBalance;
        uint64 effectiveBalance;
        uint64 exitEpoch;
        uint64 activationEpoch;
        uint64 withdrawalEpoch;
        uint64 currentCheckpointEpoch;

        uint64[] packedElements = [
                activeBalance,
                effectiveBalance,
                exitEpoch,
                activationEpoch,
                withdrawalEpoch,
                currentCheckpointEpoch
            ];

        flattenRageQuitKnot(
            e,
            depositor,
            blsPublicKey,
            stakehouse,
            amountOfETHInDepositQueue,
            withdrawalCredentials,
            slashed,
            packedElements
        );
    }

    else if (f.selector == setLifecycleExited(bytes).selector) {
        setLifecycleExited(e, blsPublicKey);
    }

    else if (f.selector == updateSlashedIsTrueFromReport(bytes,uint64).selector) {
       updateSlashedIsTrueFromReport(e, blsPublicKey, epoch);
    }

    else {
        calldataarg args;
        f(e,args);
    }
}
