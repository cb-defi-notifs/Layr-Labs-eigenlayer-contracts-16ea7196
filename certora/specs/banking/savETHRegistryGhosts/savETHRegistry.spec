using StakeHouseUniverse as universe
using StakeHouseRegistry as registry

methods {
    knotDETHBalanceInIndex(uint256,bytes) returns (uint256) envfree
    totalDETHInIndices() returns (uint256) envfree
}

/// ----------
/// Ghosts
/// ----------

// description: Idea here is to ensure the sum of the balances of all KNOTs in indices is equal to totalDETHInIndices()
ghost sumAllDETHInIndices() returns mathint {
    init_state axiom sumAllDETHInIndices() == 0;
}

hook Sstore knotDETHBalanceInIndex[KEY uint256 a][KEY bytes b] uint256 balance
(uint256 old_balance) STORAGE {
  require balance <= max_uint128;
  require old_balance <= max_uint128;
  havoc sumAllDETHInIndices assuming sumAllDETHInIndices@new() == sumAllDETHInIndices@old() +
      balance - old_balance;
}

invariant invariant_sumOfAllDETHBalanceInIndicesDoesNotExceedTotalDETHInIndices()
    sumAllDETHInIndices() == totalDETHInIndices()
    filtered { f ->
            f.selector != upgradeToAndCall(address,bytes).selector &&
            f.selector != upgradeTo(address).selector &&
            f.selector != init(address,address,address).selector
        }
    {
        preserved addKnotToOpenIndex(address a, bytes b, address c, address d) with (env e) {
            require b.length == 32;
        }

        preserved transferKnotToAnotherIndex(address _stakeHouse, bytes _blsPubKey, address _indexOwnerOrSpender, uint256 _newIndexId) with (env e) {
            require _blsPubKey.length == 32;
            require knotDETHBalanceInIndex(_newIndexId, _blsPubKey) == 0;
            //requireInvariant myNewInvariant(args)
        }

        preserved rageQuitKnot(address a, bytes b, address c) with (env e) {
            require b.length == 32;
        }

        preserved addKnotToOpenIndexAndWithdraw(address a, bytes b, address c, address d) with (env e) {
            require b.length == 32;
        }

        preserved mintSaveETHBatchAndDETHReserves(address _stakeHouse, bytes _memberId, uint256 _indexId) with (env e) {
            require _memberId.length == 32;
            require knotDETHBalanceInIndex(_indexId, _memberId) == 0;
        }

        preserved depositAndIsolateKnotIntoIndex(address _stakeHouse, bytes _memberId, address _dETHOwner, uint256 _indexId) with (env e) {
            require _memberId.length == 32;
            require knotDETHBalanceInIndex(_indexId, _memberId) == 0;
        }

        preserved isolateKnotFromOpenIndex(address _stakeHouse, bytes _memberId, address _savETHOwner, uint256 _indexId) with (env e) {
            require _memberId.length == 32;
            require knotDETHBalanceInIndex(_indexId, _memberId) == 0;
        }

        preserved approveSpendingOfKnotInIndex(address a, bytes b, address c, address d) with (env e) {
            require b.length == 32;
        }

        preserved mintDETHReserves(address a, bytes b, uint256 c) with (env e) {
            require b.length == 32;
        }
    }

rule whoChangedMyGhost(method f) {
    mathint before = sumAllDETHInIndices();
    env e;
    calldataarg args;
    f(e,args);
    mathint after = sumAllDETHInIndices();
    assert before == after;
}

ghost uint256 sumAllInflationRewards {
        init_state axiom sumAllInflationRewards == 0;
    }
    // A hook updating the user principal ghost on every write to storage
    hook Sstore dETHRewardsMintedForKnot[KEY bytes a] uint256 reward
    (uint256 old_reward) STORAGE {
        sumAllInflationRewards = sumAllInflationRewards + reward - old_reward;
    }

invariant sumOfAlldETHInHouseIsCorrect(env e, address house, bytes blsPubKey)
    totalDETHMintedWithinHouse(e, house) == (24000000000000000000 * registry.numberOfActiveKNOTsThatHaveNotRageQuit(e)) + sumAllInflationRewards
    {
        preserved with (env e2) {
            require blsPubKey.length <= 7;
            require universe.memberKnotToStakeHouse(e2, blsPubKey) == house;
            require house == registry;
        }
    }