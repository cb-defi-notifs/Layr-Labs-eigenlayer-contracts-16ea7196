certoraRun contracts/banking/savETHRegistry.sol \
  contracts/banking/savETH.sol \
  contracts/banking/dETH.sol \
  contracts/StakeHouseUniverse.sol \
  contracts/StakeHouseAccessControls.sol \
  contracts/testing/CertoraUtils.sol \
  contracts/testing/AccountManagerTest.sol \
    --verify savETHRegistry:certora/specs/banking/savETHRegistry/savETHRegistry.spec \
    --link savETHRegistry:universe=StakeHouseUniverse \
    --link StakeHouseUniverse:accessControls=StakeHouseAccessControls \
    --link savETHRegistry:saveETHToken=savETH \
    --link savETHRegistry:dETHToken=dETH \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "savETHRegistry" \
    --send_only
    #--rule_sanity advanced \
