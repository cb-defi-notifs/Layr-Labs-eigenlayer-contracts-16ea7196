if [[ "$2" ]]
then
    RULE="--rule $2"
fi

solc-select use 0.8.12  

certoraRun certora/harnesses/InvestmentManagerHarness.sol \
    lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/pods/EigenPodPaymentEscrow.sol \
    certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/EigenLayerDelegation.sol \
    certora/munged/core/Slasher.sol certora/munged/permissions/PauserRegistry.sol \
    --verify InvestmentManagerHarness:certora/specs/core/InvestmentManager.spec \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true \
    --settings -optimisticUnboundedHashing=true \
    $RULE \
    --loop_iter 3 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "InvestmentManager $1 $2" \