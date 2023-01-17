if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.9

certoraRun certora/harnesses/EigenLayerDelegationHarness.sol \
    lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/InvestmentManager.sol \
    certora/munged/core/Slasher.sol certora/munged/permissions/PauserRegistry.sol \
    --verify EigenLayerDelegationHarness:certora/specs/core/EigenLayerDelegation.spec \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true \
    $RULE \
    --loop_iter 3 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "EigenLayerDelegation $1 $2" \