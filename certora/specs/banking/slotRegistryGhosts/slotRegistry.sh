certoraRun \
    contracts/banking/SlotSettlementRegistry.sol contracts/StakeHouseUniverse.sol contracts/StakeHouseRegistry.sol contracts/banking/savETHRegistry.sol contracts/banking/sETH.sol contracts/StakeHouseAccessControls.sol \
    --verify SlotSettlementRegistry:certora/specs/banking/slotRegistryGhosts/slotRegistry.spec \
    --link SlotSettlementRegistry:universe=StakeHouseUniverse \
    --link StakeHouseUniverse:saveETHRegistry=savETHRegistry \
    --link StakeHouseUniverse:accessControls=StakeHouseAccessControls \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "slotRegistry" \
    --staging alex/new-dt-hashing-alpha \
    --settings -byteMapHashingPrecision=10
