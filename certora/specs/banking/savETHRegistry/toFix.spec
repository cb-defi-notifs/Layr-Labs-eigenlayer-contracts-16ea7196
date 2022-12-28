rule dETHMintedForKnotGteknotBalanceInIndex(env e, method f, bytes knotId, uint256 indexId) {
    require knotId.length == 32;

    require knotDETHBalanceInIndex(indexId, knotId) < dETHRewardsMintedForKnot(knotId);

    callFuncWithParams(f, e, knotId);

    assert knotDETHBalanceInIndex(indexId, knotId) < dETHRewardsMintedForKnot(knotId);
}