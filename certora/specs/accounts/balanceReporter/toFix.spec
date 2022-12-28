// TODO - there are multiple functions that MUST invalidate the internal nonce for a BLS pub key
rule balanceIncreaseInvalidateBlsPubKeyNonce(method f) {
    env e;

    address stakeHouse;

    bytes blsPubKey;
    require blsPubKey.length == 64;

    uint64 balance;
    uint64 activationEpoch;
    uint64 finalisedEpoch;
    uint248 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;

    uint256 currentNonce = blsPublicKeyInternalNonces(blsPubKey);
    require currentNonce < max_uint256;

    balIncrease(e, stakeHouse, blsPubKey, balance, activationEpoch, finalisedEpoch, deadline, v, r, s);

    uint256 newNonce = blsPublicKeyInternalNonces(blsPubKey);

    assert (newNonce - currentNonce == 1, "Nonce did not increase by 1");
}

rule buyingSlashedSlotOverOneEtherIncreasesActiveBalance {
    env e;
    env e2;

    address stakeHouse;
    require stakeHouse != 0;

    bytes blsPubKey;
    require blsPubKey.length == 64;

    uint64 balBefore = accountManager.getLastKnownActiveBalance(e2, blsPubKey);
    require balBefore >= 33000000000;// 33 ether in gwei
    // todo - assert bal before an after is same

    uint64 newActiveBal;
    require newActiveBal == (balBefore - 1000000000);//1 ether in gwei

    slashAndTopUp(e, stakeHouse, blsPubKey, newActiveBal);

    uint64 balAfter = accountManager.getLastKnownActiveBalance(e2, blsPubKey);
    assert (balAfter == balbefore, "Balance did not stay constant");
}