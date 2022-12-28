certoraRun \
  contracts/banking/savETHRegistry.sol contracts/banking/savETH.sol contracts/banking/dETH.sol contracts/StakeHouseUniverse.sol contracts/StakeHouseRegistry.sol contracts/StakeHouseAccessControls.sol \
  --verify savETHRegistry:certora/specs/banking/savETHRegistryGhosts/savETHRegistry.spec \
  --link savETHRegistry:universe=StakeHouseUniverse \
  --link StakeHouseUniverse:accessControls=StakeHouseAccessControls \
  --link savETHRegistry:saveETHToken=savETH \
  --link savETHRegistry:dETHToken=dETH \
  --settings -smt_hashingScheme=Legacy \
  --settings -superOptimisticReturnsize=true \
  --settings -depth=15 \
  --loop_iter 2 \
  --optimistic_loop \
  --msg savETHRegistry \
  --rule sumOfAlldETHInHouseIsCorrect \
  --staging alex/new-dt-hashing-alpha \
  --settings -byteMapHashingPrecision=10