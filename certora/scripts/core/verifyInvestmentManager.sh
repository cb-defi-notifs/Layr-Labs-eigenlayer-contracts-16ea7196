if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.9    

certoraRun certora/munged/core/InvestmentManager.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/EigenLayrDelegation.sol \
    certora/munged/core/Slasher.sol certora/munged/permissions/PauserRegistry.sol \
    --verify InvestmentManager:certora/specs/core/InvestmentManager.spec \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true \
    $RULE \
    --loop_iter 3 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "InvestmentManager $1 $2" \