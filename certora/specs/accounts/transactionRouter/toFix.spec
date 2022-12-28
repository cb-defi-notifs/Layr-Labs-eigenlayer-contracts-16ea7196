/// Description: Here we will prove that only a specific set of functions is allowed to change the queue
rule onlySpecificFunctionsCanChangeTopUpQueue(method f, env e, bytes knotId)
filtered {
    f ->
        f.selector != upgradeTo(address).selector &&
        f.selector != upgradeToAndCall(address, bytes).selector &&
        f.selector != init(address,address).selector &&
        !f.isView &&
        !f.isPure &&
        f.selector != flatten_balanceIncrease(address,bytes,bool,uint64[],uint248,uint8,bytes32[]).selector &&
        f.selector != flatten_rageQuitPostDeposit(address,bytes,address,bool,uint64[],uint248,uint8,bytes32[]).selector &&
        f.selector != flatten_createStakehouse(address,bytes,uint256,bool,uint64[],uint248,uint8,bytes32[]).selector &&
        f.selector != flatten_joinStakeHouseAndCreateBrand(address,bytes,address,uint256,uint64[],uint248,uint8,bytes32[]).selector &&
        f.selector != flatten_joinStakehouse(address,bytes,address,bool,uint64[],uint248,uint8,bytes32[]).selector
}
{
    require knotId.length <= 7;

    uint256 balanceBefore = stakeHouseMemberQueue(knotId);

    invokeParametricByKnotId(e, f, knotId);

    uint256 balanceAfter = stakeHouseMemberQueue(knotId);

    assert balanceBefore != balanceAfter =>
        f.selector == topUpKNOT(bytes).selector ||
        f.selector == topUpSlashedSlot(address,bytes,address,uint256).selector;
}

/// describe: Consensus layer accounting format compliance. All amounts sent to the contract that are not multiple of gwei are rejected
rule invariant_topUpsOnlyPossibleWithGweiMultiple(env e, method f, bytes knotId)
filtered {
    f ->
        f.selector != upgradeTo(address).selector &&
        f.selector != upgradeToAndCall(address, bytes).selector &&
        f.selector != init(address,address).selector
}
{
    require knotId.length <= 7;
    require stakeHouseMemberQueue(knotId) < max_uint256 - e.msg.value;
    require stakeHouseMemberQueue(knotId) % 1000000000 == 0;

    invokeParametricByKnotId(e, f, knotId);

    assert stakeHouseMemberQueue(knotId) % 1000000000 == 0;
}

/// desciption: Queue should always have a balance lower than or equal to 1, since anything more than that is sent to ETH deposit contract
rule invariant_queueIsUpperBoundedBy1(env e, method f) {
    bytes knotId;
    require knotId.length <= 7;

    uint256 ether = 1000000000000000000;

    require stakeHouseMemberQueue(knotId) <= ether;

    invokeParametricByKnotId(e, f, knotId);

    assert stakeHouseMemberQueue(knotId) <= ether;
}