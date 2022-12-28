using AccountManager as accountManager

methods {
    blsPublicKeyInternalNonces(bytes) returns uint256 envfree
}

function invokeParametric(env e, method f) {
    calldataarg arg;

    if (f.isFallback) {
        f@withrevert(e, arg);
    } else {
        f(e, arg);
    }
}

rule reportingNonceInvalidatedWhenCallingBalanceIncrease(method f) {
    env e;

    address house;
    bytes blsPubKey; require blsPubKey.length == 32;
    bool slashed;
    uint64[] params;
    uint248 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;

    uint256 nonceBefore = blsPublicKeyInternalNonces(blsPubKey);
    require nonceBefore < max_uint256;

    balanceIncrease(
        e,
        house,
        blsPubKey,
        params,
        deadline,
        v,
        r,
        s
    );

    uint256 nonceAfter = blsPublicKeyInternalNonces(blsPubKey);
    assert nonceAfter == nonceBefore + 1;
}