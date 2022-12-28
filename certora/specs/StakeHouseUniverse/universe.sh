certoraRun contracts/StakeHouseUniverse.sol \
contracts/StakeHouseAccessControls.sol \
contracts/community/CommunityCentral.sol \
contracts/StakeHouseRegistry.sol \
contracts/banking/SlotSettlementRegistry.sol \
contracts/banking/savETHRegistry.sol \
contracts/banking/dETH.sol \
contracts/banking/sETH.sol \
contracts/accounts/AccountManager.sol \
    --verify StakeHouseUniverse:certora/specs/StakeHouseUniverse/universe.spec \
    --link StakeHouseUniverse:accessControls=StakeHouseAccessControls \
    --link StakeHouseUniverse:slotRegistry=SlotSettlementRegistry \
    --link StakeHouseUniverse:saveETHRegistry=savETHRegistry \
    --link savETHRegistry:dETHToken=dETH \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "StakeHouseUniverse"
