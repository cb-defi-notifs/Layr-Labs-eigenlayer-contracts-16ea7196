if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.9    

certoraRun certora/harnesses/SlasherHarness.sol certora/ComplexityCheck/DummyERC20A.sol certora/ComplexityCheck/DummyERC20B.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/EigenLayrDelegation.sol \
    certora/munged/core/InvestmentManager.sol certora/munged/permissions/PauserRegistry.sol \
    --verify SlasherHarness:certora/specs/core/Slasher.spec \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true,-recursionErrorAsAssert=false,-recursionEntryLimit=3 \
    --loop_iter 3 \
    --link SlasherHarness:delegation=EigenLayrDelegation \
    $RULE \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "Slasher $1 $2" \