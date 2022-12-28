using AccountManager as accountManager

methods {
    blsPublicKeyInternalNonces(bytes) returns uint256 envfree
    stakeHouseMemberQueue(bytes) returns uint256 envfree
    specialExitFee(bytes) returns uint256 envfree
}

/// description: unknown top up does not affect adjusted active balance when there is nothing in the queue
rule topUpNeverIncreasesKnotActiveBalance {
    env e;
    require e.msg.value >= 1000000000000000000; // >= 1 ether

    bytes blsPubKey;
    require blsPubKey.length == 64;

    // for this rule, ensure there is nothing in the queue to start with as it would increase the adjusted balance
    uint256 amountInQueue = stakeHouseMemberQueue(blsPubKey);
    require amountInQueue == 0;

    env e2;

    uint64 balBefore = accountManager.getLastKnownActiveBalance(e2, blsPubKey);

    topUpKNOT(e, blsPubKey);

    // ensure that there is no queue balance for an unknown top up
    assert stakeHouseMemberQueue(blsPubKey) == 0;

    // assert that there is no change in the adjust
    uint64 balAfter = accountManager.getLastKnownActiveBalance(e2, blsPubKey);
    assert (balAfter == balBefore, "Balance violated");
}

/// description: when there is ETH in the queue from topping up, flushing updates the adjusted active balance
rule topUpThatFlushesTheQueueIncreasesKnotActiveBalance {
    env e;
    require e.msg.value >= 1000000000000000000; // >= 1 ether

    bytes blsPubKey;
    require blsPubKey.length == 64;

    uint256 amountInQueue = stakeHouseMemberQueue(blsPubKey);
    require amountInQueue < 1000000000000000000; // there can be up to 1 ETH in the queue

    env e2;

    uint256 balBefore = accountManager.getLastKnownActiveBalance(e2, blsPubKey);

    topUpKNOT(e, blsPubKey);

    uint256 amountInQueueAfter = stakeHouseMemberQueue(blsPubKey);
    assert amountInQueueAfter == 0;

    uint256 balAfter = accountManager.getLastKnownActiveBalance(e2, blsPubKey);
    assert (balAfter == (balBefore + amountInQueue), "Balance fell");
}

rule toppingUpAndFlushingMechanismCanPayDownTheSpecialExitFee {
    env e;

    bytes blsPubKey; require blsPubKey.length == 32;

    require stakeHouseMemberQueue(blsPubKey) == 0;

    uint256 currentExitFee = specialExitFee(blsPubKey);
    require currentExitFee > 0 && currentExitFee <= 4000000000000000000; // up to 4 SLOT

    require e.msg.value >= currentExitFee;

    topUpKNOT(e, blsPubKey);

    assert specialExitFee(blsPubKey) == 0;
    assert stakeHouseMemberQueue(blsPubKey) == 0;
}

rule partialPaymentOfSpecialExitFeePossible {
    env e;

    bytes blsPubKey; require blsPubKey.length == 32;

    require stakeHouseMemberQueue(blsPubKey) == 0;

    uint256 exitFeeBefore = specialExitFee(blsPubKey);
    require exitFeeBefore >= 100000000000000000 && exitFeeBefore <= 4000000000000000000 && exitFeeBefore % 2 == 0; // >= 0.1 && <= 4 SLOT && multiple of 2 for division

    require e.msg.value == (exitFeeBefore / 2);

    topUpKNOT(e, blsPubKey);

    assert specialExitFee(blsPubKey) == (exitFeeBefore / 2);
}

//
// --- Invalidating Nonces ---
//

// description: Post-RV audit - ensure that the nonce is invalidated when SLOT is purchased
rule toppingUpSlashedSlotInvalidatesTheNonceForTheBLSPubKey {
    env e;

    address house;

    bytes blsPubKey;
    require blsPubKey.length == 32;

    address recipient;
    uint256 amount;

    uint256 nonceBefore = blsPublicKeyInternalNonces(blsPubKey);
    require nonceBefore < max_uint256;

    topUpSlashedSlot(e, house, blsPubKey, recipient, amount);

    uint256 nonceAfter = blsPublicKeyInternalNonces(blsPubKey);
    assert nonceAfter == (nonceBefore + 1);
}
