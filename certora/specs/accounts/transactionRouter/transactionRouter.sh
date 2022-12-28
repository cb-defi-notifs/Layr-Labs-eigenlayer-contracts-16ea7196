certoraRun contracts/testing/TransactionRouterTest.sol \
    --verify TransactionRouterTest:certora/specs/accounts/transactionRouter/transactionRouter.spec \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --loop_iter 3 --optimistic_loop \
    --msg "TransactionRouter queueIsUpperBoundedBy1" --rule "invariant_queueIsUpperBoundedBy1"
