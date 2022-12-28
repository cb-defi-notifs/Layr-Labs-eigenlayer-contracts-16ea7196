certoraRun contracts/accounts/TransactionRouter.sol contracts/accounts/AccountManager.sol \
    --verify TransactionRouter:certora/specs/accounts/balanceReporter/balanceReporter.spec \
    --link TransactionRouter:accountManager=AccountManager \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --loop_iter 3 --optimistic_loop \
    --msg "BalanceReporter"
