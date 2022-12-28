/// description: Making sure that the only status increment possible is 1
rule registerDepositIncrementsLifecycleStatusByOne {
    env e;

	address depositor;

	bytes blsPublicKey;
	require blsPublicKey.length <= 7;

	bytes ciphertext;
	require ciphertext.length <= 7;

	bytes aesEncryptorKey;
	require aesEncryptorKey.length <= 7;

	bytes32 depositContractRoot;

    uint8 lifecycleStatusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

	registerDeposit(e, depositor, blsPublicKey, ciphertext, aesEncryptorKey, depositContractRoot);

	uint8 lifecycleStatus = blsPublicKeyToLifecycleStatus(blsPublicKey);

	assert lifecycleStatus == 2 && lifecycleStatusBefore == 1; // DEPOSIT_COMPLETED is 2
}

/// description: Checking if a predecessor of the registered account exit.
/// description: Meaning that all accounts that have index below the total number of accounts must have completed the phase 1
rule predecessorOfRegisteredAccountExist(uint i, method f, env e)
filtered {
         f ->
             f.selector != upgradeTo(address).selector &&
             f.selector != upgradeToAndCall(address, bytes).selector
    }
{

    require i <= 100000000;
    require numberOfAccounts() <= 100000000;
    require addressNCompletedPhase1(i) => i < numberOfAccounts();

    invokeParametric(e, f);

    assert addressNCompletedPhase1(i) => i < numberOfAccounts();
}

/// description: Making sure that only unique accounts are present in the accounts array
/// description: If bls public keys are not the same => account indices are not the same
rule invariant_onlyUniqueAccountsExist(env e, method f) { /// LONG

    bytes a;
    bytes b;

    uint i;
    uint j;

    require a.length <= 7;
    require b.length <= 7;
    require i < 100000000;
    require j < 100000000;
    require numberOfAccounts() <= 100000000;
    require i < numberOfAccounts();
    require j < numberOfAccounts();

    require i != j => !compareKnotIds(a, b);

    invokeParametric(e, f);

    assert i != j => !compareKnotIds(a, b);
}

/// description: only core modules are allowed to call state changing methods
/// description: Making sure that only core modules can call core methods
rule invariant_nonCoreModuleShouldNotBeAbleToCallAnyStateChangeMethod(method f)
filtered {
     f ->
         f.selector != init(address).selector &&
         f.selector != setBlockDelta(uint256).selector &&
         !f.isView &&
         !f.isPure &&
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector
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

/// description: If account index is bigger than it means that the deposit block must be bigger or equal (if registered in the same transaction)
rule invariant_accountBlockAdditionNonDecreasing(uint i, uint j, env e, method f)
filtered {
             f ->
                 f.selector != upgradeTo(address).selector &&
                 f.selector != upgradeToAndCall(address, bytes).selector
        }
{
    require i > j => getAccountDepositBlockByIndex(i) >= getAccountDepositBlockByIndex(j);

    invokeParametric(e, f);

    assert i > j => getAccountDepositBlockByIndex(i) >= getAccountDepositBlockByIndex(j);
}

/// description: If account completed at least basic registration process => the deposit block is set to a number bigger than 0
rule registeredAccountHasDepositBlockSet(bytes knotId, env e, method f)
filtered {
         f ->
             f.selector != upgradeTo(address).selector &&
             f.selector != upgradeToAndCall(address, bytes).selector
    }
{
    require numberOfAccounts() < 100000000;
    require getCurrentBlock(e) > 0;

    require blsPublicKeyToLifecycleStatus(knotId) >= 2 => getAccountDepositBlockByKnotId(knotId) > 0;

    invokeParametric(e, f);

    assert blsPublicKeyToLifecycleStatus(knotId) >= 2 => getAccountDepositBlockByKnotId(knotId) > 0;
}

/// description: Account lifecycle status is like age - can only go up
rule accountStatusIsNonDecreasing(bytes blsPublicKey, method f, env e)
filtered {
         f ->
             f.selector != upgradeTo(address).selector &&
             f.selector != upgradeToAndCall(address, bytes).selector &&
             f.selector != rageQuitKnot(address,bytes,address,uint256,(bytes,bytes,bool,uint64,uint64,uint64,uint64,uint64,uint64)).selector
    }

{
    require blsPublicKey.length == 48;

    uint256 statusBefore = blsPublicKeyToLifecycleStatus(blsPublicKey);

    callFuncWithParams(f, e, blsPublicKey);

    uint256 statusAfter = blsPublicKeyToLifecycleStatus(blsPublicKey);

    assert statusBefore <= statusAfter;
}

/// description: Lifecycle status above or equal 3 will always imply that dETH was minted at some point
rule invariant_lifecycleStatusImpliesMinteddETH(env e, method f)
filtered {
         f ->
             f.selector != upgradeTo(address).selector && /// Open-Zeppelin proxy function
             f.selector != upgradeToAndCall(address, bytes).selector /// Open-Zeppelin proxy function
    }

{
    bytes blsPublicKey;
    require blsPublicKey.length <= 7;

    callFuncWithParams(f, e, blsPublicKey);

    assert (blsPublicKeyToLifecycleStatus(blsPublicKey) >= 3) <=> indexRegistry.knotdETHSharesMinted(blsPublicKey);
}