certoraRun certora/munged/core/EigenLayrDelegation.sol certora/ComplexityCheck/DummyERC20A.sol certora/ComplexityCheck/DummyERC20B.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/InvestmentManager.sol \
    certora/munged/core/Slasher.sol certora/munged/permissions/PauserRegistry.sol \
    --verify EigenLayrDelegation:certora/ComplexityCheck/complexity.spec \
    --staging \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true \
    --loop_iter 3 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "EigenLayrDelegation complexity loop 3" \
    
certoraRun certora/munged/core/InvestmentManager.sol certora/ComplexityCheck/DummyERC20A.sol certora/ComplexityCheck/DummyERC20B.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/EigenLayrDelegation.sol \
    certora/munged/core/Slasher.sol certora/munged/permissions/PauserRegistry.sol \
    --verify InvestmentManager:certora/ComplexityCheck/complexity.spec \
    --staging \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true \
    --loop_iter 3 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "InvestmentManager complexity loop 3" \

certoraRun certora/munged/core/Slasher.sol certora/ComplexityCheck/DummyERC20A.sol certora/ComplexityCheck/DummyERC20B.sol \
    certora/munged/pods/EigenPodManager.sol certora/munged/pods/EigenPod.sol certora/munged/strategies/InvestmentStrategyBase.sol certora/munged/core/EigenLayrDelegation.sol \
    certora/munged/core/InvestmentManager.sol certora/munged/permissions/PauserRegistry.sol \
    --verify Slasher:certora/ComplexityCheck/complexity.spec \
    --staging \
    --optimistic_loop \
    --send_only \
    --settings -optimisticFallback=true \
    --loop_iter 3 \
    --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
    --msg "Slasher complexity loop 3" \
    
# certoraRun certora/munged/DataLayr/BLSRegistryWithBomb.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify BLSRegistryWithBomb:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "BLSRegistryWithBomb complexity" \
    
# certoraRun certora/munged/DataLayr/DataLayrBombVerifier.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify DataLayrBombVerifier:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "DataLayrBombVerifier complexity" \
    
# certoraRun certora/munged/DataLayr/DataLayrChallengeUtils.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify DataLayrChallengeUtils:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "DataLayrChallengeUtils complexity" \
    
# certoraRun certora/munged/DataLayr/DataLayrLowDegreeChallenge.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify DataLayrLowDegreeChallenge:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "DataLayrLowDegreeChallenge complexity" \
    
# certoraRun certora/munged/DataLayr/DataLayrPaymentManager.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify DataLayrPaymentManager:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "DataLayrPaymentManager complexity" \
    
# certoraRun certora/munged/DataLayr/DataLayrServiceManager.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify DataLayrServiceManager:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "DataLayrServiceManager complexity" \
    
# certoraRun certora/munged/DataLayr/EphemeralKeyRegistry.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify EphemeralKeyRegistry:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "EphemeralKeyRegistry complexity" \
    
# certoraRun certora/munged/pods/EigenPod.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify EigenPod:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "EigenPod complexity" \
    
# certoraRun certora/munged/pods/EigenPodManager.sol ComplexityCheck/DummyERC20A.sol ComplexityCheck/DummyERC20B.sol \
#     --verify EigenPodManager:ComplexityCheck/complexity.spec \
#     --staging \
#     --optimistic_loop \
#     --send_only \
#     --packages @openzeppelin=lib/openzeppelin-contracts @openzeppelin-upgrades=lib/openzeppelin-contracts-upgradeable \
#     --msg "EigenPodManager complexity" \
    