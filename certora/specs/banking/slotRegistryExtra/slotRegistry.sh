certoraRun contracts/banking/SlotSettlementRegistry.sol contracts/StakeHouseUniverse.sol contracts/StakeHouseRegistry.sol contracts/banking/savETHRegistry.sol contracts/banking/sETH.sol contracts/StakeHouseAccessControls.sol \
    --link SlotSettlementRegistry:universe=StakeHouseUniverse \
    --link StakeHouseUniverse:saveETHRegistry=savETHRegistry \
    --link StakeHouseUniverse:accessControls=StakeHouseAccessControls \
    --verify SlotSettlementRegistry:certora/specs/banking/slotRegistryExtra/slotRegistry.spec \
    --settings -smt_hashingScheme=Legacy \
    --settings -depth=15 \
    --loop_iter 3 --optimistic_loop \
    --msg "slotRegistry nonCoreModuleShouldNotBeAbleToCallAnyStateChangeMethod"
