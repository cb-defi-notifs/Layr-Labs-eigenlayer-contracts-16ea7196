certoraRun contracts/testing/SafeBoxTest.sol \
  --verify SafeBoxTest:certora/specs/cip/SafeBox.spec \
  --loop_iter 3 --optimistic_loop \
  --settings -smt_hashingScheme=Legacy \
  --settings -superOptimisticReturnsize=true \
  --settings -byteMapHashingPrecision=7 \
  --msg "SafeBox"
