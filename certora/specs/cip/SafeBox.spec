methods {
	returnUintDKGStatus(address) returns uint256 envfree;
	isGuardianBootstrap(address) returns bool envfree;
	isGuardianRelinquished(address) returns bool envfree;
	isGuardianRegistered(address) returns bool envfree;

	getDecryptionRequestTracker(address, bytes, uint256) returns bool;
	knotIdToInternalNonce(bytes) returns uint256 envfree;
	guardianIndexPointer() returns uint256 envfree;
	isDecryptionRequestValid(bytes) returns bool;
	dkgComplaints(address, address) returns bool envfree;
	compareKnotIds(bytes, bytes) returns bool envfree;

	decryptionValidityPeriod() returns uint256 envfree;
}

function invokeParametric(env e, method f) {
    bytes knotId;

    require knotId.length <= 7;

    invokeParametricByBlsKey(e, f, knotId);
}

function invokeParametricByBlsKey(env e, method f, bytes knotId) {
    address stakehouse;
    bytes aesPublicKey;
    bytes ciphertext;
    bytes zkProof;
    bytes guardianAesPublicKey;
    address[] tokens;

    require aesPublicKey.length <= 7;
    require ciphertext.length <= 7;
    require zkProof.length <= 7;
    require guardianAesPublicKey.length <= 7;
    require tokens.length <= 4;

    if (f.selector == applyForDecryption(bytes,address,bytes).selector) {
        applyForDecryption(e, knotId, stakehouse, aesPublicKey);
    }

    else if (f.selector == submitDecryption(bytes,bytes,bytes,bytes).selector) {
        submitDecryption(e, aesPublicKey, knotId, ciphertext, zkProof);
    }

    else if (f.selector == reEncryptSigningKey(bytes,address,bytes,bytes).selector) {
        reEncryptSigningKey(e, knotId, stakehouse, ciphertext, aesPublicKey);
    }

    else if (f.selector == joinGuardians(address[],bytes).selector) {
        joinGuardians(e, tokens, guardianAesPublicKey);
    }

    else {
        calldataarg arg;
        f(e, arg);
    }
}

/// Status during the distributed key generation procedure can only be increasing
rule onlyIncreasingDKGStatus(env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector && /// OZ function
         f.selector != upgradeToAndCall(address, bytes).selector && /// OZ function
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }

{
    uint256 beforeStatus = returnUintDKGStatus(e.msg.sender);
    invokeParametric(e, f);
    uint256 afterStatus = returnUintDKGStatus(e.msg.sender);

    assert (afterStatus >= beforeStatus, "Status must be non-decreasing");
}

/// description: Any method call can only increase the DKG status by 1
rule incrementsHappenBy1(env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    uint256 beforeStatus = returnUintDKGStatus(e.msg.sender);
    invokeParametric(e, f);
    uint256 afterStatus = returnUintDKGStatus(e.msg.sender);

    require beforeStatus < afterStatus;

    assert (beforeStatus + 1 == afterStatus, "Status can only increase by 1");
    assert (isGuardianBootstrap(e.msg.sender), "Guardian not bootstrap");
}

/// description: Submitting round 1 data can only increment the index from 1 to 2
rule submitRound1DataIncrementsCorrectly(env e) {
    uint256 beforeStatus = returnUintDKGStatus(e.msg.sender);

    calldataarg arg;
    submitRound1Data(e, arg);

    uint256 afterStatus = returnUintDKGStatus(e.msg.sender);

    assert (afterStatus == 2 && beforeStatus == 1, "Status incorrect");
    assert (isGuardianBootstrap(e.msg.sender), "Guardian not bootstrap");
}

/// description: Submitting round 3 data increments tatus from 3 to 4
rule submitRound3DataIncrementsCorrectly(env e) {
    uint256 beforeStatus = returnUintDKGStatus(e.msg.sender);

    calldataarg arg;
    submitRound3Data(e, arg);

    uint256 afterStatus = returnUintDKGStatus(e.msg.sender);

    assert (afterStatus == 4 && beforeStatus == 3, "Status incorrect");
    assert (isGuardianBootstrap(e.msg.sender), "Guardian not bootstrap");
}

/// description: Submitting DKG complaint can only increment the status from 2 to 3 or from 4 to 5
rule submitDkgComplaintIncrementsCorrectly(env e) {
    uint256 beforeStatus = returnUintDKGStatus(e.msg.sender);

    calldataarg arg;
    submitDKGComplaint(e, arg);

    uint256 afterStatus = returnUintDKGStatus(e.msg.sender);

    assert (afterStatus == 3 && beforeStatus == 2 || afterStatus == 5 && beforeStatus == 4, "Status incorrect");
    assert (isGuardianBootstrap(e.msg.sender), "Guardian not bootstrap");
}

/// description: Submitting no DKG complaint (to proceed further in the DKG process) increments the status 2 -> 3 or 3 -> 2
rule submitNoComplaintIncrementsCorrectly(env e) {
    uint256 beforeStatus = returnUintDKGStatus(e.msg.sender);

    calldataarg arg;
    submitNoComplaint(e, arg);

    uint256 afterStatus = returnUintDKGStatus(e.msg.sender);

    assert (afterStatus == 3 && beforeStatus == 2 || afterStatus == 5 && beforeStatus == 4, "Status incorrect");
    assert (isGuardianBootstrap(e.msg.sender), "Guardian not bootstrap");
}

/// description: Refuse guardian duties can only be executed for a guardian
rule refuseGuardianDutiesOnlyWorksForGuardians(env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector && /// OZ function
         f.selector != upgradeToAndCall(address, bytes).selector && /// OZ function
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require !isGuardianRelinquished(e.msg.sender);

    invokeParametric(e, f);

    assert isGuardianRelinquished(e.msg.sender) => isGuardianRegistered(e.msg.sender) && f.selector == refuseGuardianDuties().selector;
}

/// description: Joining guardians for a second time is rejected
rule joinGuardiansDoesNotWorkForGuardians(env e) {
    bool registrationStatus = isGuardianRegistered(e.msg.sender);

    calldataarg arg;
    joinGuardians(e, arg);

    bool registrationStatusAfter = isGuardianRegistered(e.msg.sender);

    assert(!registrationStatus, "Guardian was registered before");
    assert(registrationStatusAfter, "Guardian was not registered");
}

/// description: Index counting guardians can only increase
rule guardianIndexPointerOnlyIncreasing(method f, env e)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{

    uint256 pointerBefore = guardianIndexPointer();
    invokeParametric(e, f);
    uint256 pointerAfter = guardianIndexPointer();

    require pointerBefore <= 1000000000000;
    require pointerAfter <= 1000000000000;

     assert pointerBefore <= pointerAfter;
}

/// description: Block calling all the state-changing functions while the decryption request is active
rule activeRequestLocksInternalNonceIncrements(env e, method f, bytes knotId)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require knotId.length <= 7;

    require decryptionValidityPeriod() > 10;
    require decryptionValidityPeriod() < 1000000;

    bool validity = isDecryptionRequestValid(e, knotId);

    uint256 nonceBefore = knotIdToInternalNonce(knotId);

    require nonceBefore < 1000000000;

    invokeParametricByBlsKey(e, f, knotId);

    uint256 nonceAfter = knotIdToInternalNonce(knotId);
    require nonceAfter < 1000000000;

    assert nonceAfter > nonceBefore => !validity;
}

/// description: All guardians that are marked as a bootstrap have a status that's bigger than 0
invariant bootstrapGuardiansHaveNonzeroStatus(address guardian)
    isGuardianBootstrap(guardian) => returnUintDKGStatus(guardian) >= 1

    filtered {
               f ->
                  f.selector != upgradeTo(address).selector &&
                  f.selector != upgradeToAndCall(address, bytes).selector &&
                  f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector &&
                  !f.isPure &&
                  !f.isView &&
                  !f.isFallback
   }

/// description: All bootstrap guardians must be marked as registered, and this condition can't change
rule bootstrapGuardiansAreRegistered(method f, env e, address guardian)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require isGuardianBootstrap(guardian) => isGuardianRegistered(guardian);

    invokeParametric(e, f);

    assert isGuardianBootstrap(guardian) => isGuardianRegistered(guardian);
}

ghost countAllExistingGuardianRegistrations() returns mathint {
    init_state axiom countAllExistingGuardianRegistrations() == 0;
}

hook Sstore isGuardianRegistered[KEY address guardian] bool registration
(bool oldRegistration) STORAGE {
  havoc countAllExistingGuardianRegistrations assuming countAllExistingGuardianRegistrations@new() == countAllExistingGuardianRegistrations@old() + 1;
}

/// description: Guardian index pointer must always match the register guardian count, since that's what is being counted
rule guardianiIndexPointerMatchesRegisteredGuardianCount(method f, env e)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require guardianIndexPointer() < max_uint256;
    require countAllExistingGuardianRegistrations() == guardianIndexPointer();

    invokeParametric(e, f);

    assert countAllExistingGuardianRegistrations() == guardianIndexPointer();
}

/// description: All guardians that refused duties were once registered guardians
rule relinquishedGuardiansWereOnceRegistered(address guardian, env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require isGuardianRelinquished(guardian) => isGuardianRegistered(guardian);

    invokeParametric(e, f);

    assert isGuardianRelinquished(guardian) => isGuardianRegistered(guardian);
}

/// description: Complaints are impossible to submit by non-bootstrap guardians
rule complaintsAreOnlyPossibleByBootstrapGuardians(address accuser, address accusee, env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector && /// proxy function
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    require dkgComplaints(accuser, accusee) => isGuardianBootstrap(accuser) && isGuardianBootstrap(accusee);

    invokeParametric(e, f);

    assert dkgComplaints(accuser, accusee) => isGuardianBootstrap(accuser) && isGuardianBootstrap(accusee);
}

/// description: No method ever can change isGuardianRegistered mapping, since this tracks historical registrations
rule noUnauthorizedMethodChangesRegistrationStatus(address guardian, env e, method f)
filtered {
     f ->
         f.selector != upgradeTo(address).selector &&
         f.selector != upgradeToAndCall(address, bytes).selector &&
         f.selector != init(address,address[],bytes[],uint256,uint256,uint256,uint256).selector &&
         f.selector != aggregateReEncryption(bytes,address,bytes,bytes,(uint248,uint8,bytes32,bytes32)[]).selector && /// tool limitations
         f.selector != aggregateDecryptionApplication(bytes,address,bytes,(uint248,uint8,bytes32,bytes32)[]).selector /// tool limitations
     }
{
    bool guardianStatusBefore = isGuardianRegistered(guardian);

    invokeParametric(e, f);

    bool guardianStatusAfter = isGuardianRegistered(guardian);

    assert guardianStatusBefore != guardianStatusAfter => f.selector == joinGuardians(address[], bytes).selector;
}

/// Description: index pointer can only be incremented if there are no active decryption requests
//rule incrementsPossibleOnlyWhenNoActiveDecryptionRequests() {

//}