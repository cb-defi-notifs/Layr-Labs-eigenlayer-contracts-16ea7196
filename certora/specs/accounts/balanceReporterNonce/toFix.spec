rule reportingNonceInvalidatedWhenCallingSlash(method f) {
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

    slash(
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

rule reportingNonceInvalidatedWhenCallingVoluntaryWithdrawal(method f) {
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

    voluntaryWithdrawal(
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