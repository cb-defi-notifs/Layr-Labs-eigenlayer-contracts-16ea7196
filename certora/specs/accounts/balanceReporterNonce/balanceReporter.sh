certoraRun contracts/testing/BalanceReporterMock.sol contracts/accounts/AccountManager.sol \
    --verify BalanceReporterMock:certora/specs/accounts/balanceReporterNonce/balanceReporter.spec \
    --link BalanceReporterMock:accountManager=AccountManager \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "BalanceReporter"
