certoraRun \
contracts/testing/AccountManagerTest.sol \
contracts/StakeHouseUniverse.sol \
contracts/StakeHouseAccessControls.sol \
contracts/StakeHouseRegistry.sol \
contracts/testing/GateKeeperMock.sol \
contracts/banking/SlotSettlementRegistry.sol \
contracts/banking/savETHRegistry.sol \
    --verify AccountManagerTest:certora/specs/accounts/accountManager/accountManager.spec \
    --link AccountManagerTest:universe=StakeHouseUniverse \
    --link StakeHouseUniverse:accessControls=StakeHouseAccessControls \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -byteMapHashingPrecision=7 \
    --loop_iter 3 --optimistic_loop \
    --msg "AccountManager"