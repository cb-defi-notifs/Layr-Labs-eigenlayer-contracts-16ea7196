certoraRun contracts/gateway/savETHOriginGateway.sol contracts/StakeHouseUniverse.sol contracts/banking/savETHRegistry.sol \
    --verify savETHOriginGateway:certora/specs/gateway/gateway.spec \
    --link savETHOriginGateway:universe=StakeHouseUniverse \
    --link StakeHouseUniverse:saveETHRegistry=savETHRegistry \
    --settings -smt_hashingScheme=Legacy \
    --settings -superOptimisticReturnsize=true \
    --settings -depth=15 \
    --loop_iter 2 \
    --optimistic_loop \
    --msg "General savETHGateway and Origin Gateway Rules" \
    --send_only
    #--rule_sanity advanced
