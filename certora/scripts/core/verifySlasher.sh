if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.9    

certoraRun certora/harnesses/SlasherHarness.sol \
    lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/EigenLayerDelegation.sol \
    certora/munged/core/InvestmentManager.sol certora/munged/permissions/PauserRegistry.sol \
    --verify SlasherHarness:certora/specs/core/Slasher.spec \
    --optimistic_loop \
    --cloud master \
    --send_only \
    --settings -optimisticFallback=true,-recursionErrorAsAssert=false,-recursionEntryLimit=3 \
    --loop_iter 3 \
    --link SlasherHarness:delegation=EigenLayerDelegation \
    $RULE \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "Slasher $1 $2" \